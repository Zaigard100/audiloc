import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';
import '../dedupe/dedupe_service.dart';
import 'tag_reader.dart';

class LibraryImportResult {
  const LibraryImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.failed,
  });

  final int imported;
  final int skippedDuplicates;
  final int failed;

  int get total => imported + skippedDuplicates + failed;
}

/// Scans a folder for audio files, extracts tags, hashes each file's
/// content as its track id, and writes new tracks into the library
/// (ТЗ п.6.4). Runs entirely locally — no network involved; the resulting
/// `tracks` row reaching other devices is `services/sync`'s job.
class LibraryImportService {
  LibraryImportService({
    required TracksRepository tracksRepository,
    required TagReader tagReader,
    required DedupeService dedupeService,
    required String deviceId,
    required Directory coverCacheDir,
  })  : _tracksRepository = tracksRepository,
        _tagReader = tagReader,
        _dedupeService = dedupeService,
        _deviceId = deviceId,
        _coverCacheDir = coverCacheDir;

  static const supportedExtensions = {
    '.mp3',
    '.flac',
    '.ogg',
    '.oga',
    '.opus',
    '.m4a',
    '.wav',
    '.wma',
  };

  final TracksRepository _tracksRepository;
  final TagReader _tagReader;
  final DedupeService _dedupeService;
  final String _deviceId;
  final Directory _coverCacheDir;

  Future<LibraryImportResult> importDirectory(
    Directory dir, {
    bool recursive = true,
  }) async {
    final files = <File>[];
    await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
      if (entity is File && supportedExtensions.contains(p.extension(entity.path).toLowerCase())) {
        files.add(entity);
      }
    }
    return importFiles(files);
  }

  Future<LibraryImportResult> importFiles(List<File> files) async {
    var imported = 0;
    var skipped = 0;
    var failed = 0;

    final existingById = {for (final t in await _tracksRepository.all()) t.id: t};

    for (final file in files) {
      try {
        final track = await _buildTrack(file, existingById.values);
        if (track == null) {
          skipped++;
          continue;
        }
        await _tracksRepository.upsert(track);
        existingById[track.id] = track;
        imported++;
      } catch (_) {
        failed++;
      }
    }

    return LibraryImportResult(imported: imported, skippedDuplicates: skipped, failed: failed);
  }

  /// Returns null when the file is already in the library (same content
  /// hash) or looks like a duplicate of an existing track.
  Future<Track?> _buildTrack(File file, Iterable<Track> existingTracks) async {
    final id = await _hashFile(file);
    if (existingTracks.any((t) => t.id == id)) return null;

    final tags = await _tagReader.read(file.path);
    final candidate = Track(
      id: id,
      path: file.path,
      title: tags?.title,
      artist: tags?.artist,
      album: tags?.album,
      genre: tags?.genre,
      durationMs: tags?.durationMs,
      fileSize: await file.length(),
      addedOnDevice: _deviceId,
      coverPath: await _cacheCover(id, tags?.coverBytes),
    );

    final duplicate = _dedupeService.findDuplicate(candidate, existingTracks);
    if (duplicate != null) return null;

    return candidate;
  }

  Future<String> _hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<String?> _cacheCover(String trackId, Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    final coverFile = File(p.join(_coverCacheDir.path, '$trackId.cover'));
    if (!await coverFile.exists()) {
      await coverFile.writeAsBytes(bytes);
    }
    return coverFile.path;
  }
}
