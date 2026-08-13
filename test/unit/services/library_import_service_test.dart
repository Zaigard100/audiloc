import 'dart:io';
import 'dart:typed_data';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/services/dedupe/dedupe_service.dart';
import 'package:audiloc/services/library_import/library_import_service.dart';
import 'package:audiloc/services/library_import/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// `audiotags` is a native FFI plugin; it isn't loadable under plain
/// `flutter test`, so tests fake tag extraction and exercise the real
/// hashing/dedupe/repository wiring around it.
class _FakeTagReader extends TagReader {
  _FakeTagReader(this._tags);

  final Map<String, TrackTags?> _tags;

  @override
  Future<TrackTags?> read(String path) async => _tags[path];
}

void main() {
  late Directory tempDir;
  late Directory audioDir;
  late AudilocDatabase db;
  late TracksRepository tracksRepository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audiloc_import_test_');
    audioDir = await Directory('${tempDir.path}/audio').create();
    db = await AudilocDatabase.openInMemory();
    tracksRepository = TracksRepository(db.crdt);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  LibraryImportService buildService(Map<String, TrackTags?> tags) => LibraryImportService(
        tracksRepository: tracksRepository,
        tagReader: _FakeTagReader(tags),
        dedupeService: DedupeService(),
        deviceId: 'device-1',
        coverCacheDir: tempDir,
        audioStorageDir: audioDir,
      );

  test('imports files with distinct content as separate tracks', () async {
    final fileA = await writeFile('a.mp3', [1, 2, 3]);
    final fileB = await writeFile('b.mp3', [4, 5, 6]);
    final service = buildService({
      fileA.path: const TrackTags(title: 'Song A', artist: 'Artist', durationMs: 200000),
      fileB.path: const TrackTags(title: 'Song B', artist: 'Artist', durationMs: 210000),
    });

    final result = await service.importFiles([fileA, fileB]);

    expect(result.imported, 2);
    expect(result.skippedDuplicates, 0);
    final all = await tracksRepository.all();
    expect(all.map((t) => t.title), containsAll(['Song A', 'Song B']));
  });

  test(
      'imported tracks are read from a copy in audioStorageDir, not the original path — '
      'and the original file is left untouched (docs/adr/0014)', () async {
    final original = await writeFile('a.mp3', [1, 2, 3]);
    final service = buildService({original.path: const TrackTags(title: 'Song A')});

    await service.importFiles([original]);
    final track = (await tracksRepository.all()).single;

    expect(track.path, isNot(original.path));
    expect(p.isWithin(audioDir.path, track.path!), isTrue);
    expect(await File(track.path!).readAsBytes(), [1, 2, 3]);
    expect(await original.exists(), isTrue, reason: 'a copy, never a move — the user\'s own file is untouched');
    expect(await original.readAsBytes(), [1, 2, 3]);
  });

  test('importing identical bytes twice does not duplicate (hash-based id)', () async {
    final file = await writeFile('a.mp3', [1, 2, 3]);
    final service = buildService({file.path: const TrackTags(title: 'Song A')});

    await service.importFiles([file]);
    final result = await service.importFiles([file]);

    expect(result.skippedDuplicates, 1);
    expect(await tracksRepository.all(), hasLength(1));
  });

  test('dedupe heuristic skips a differently-encoded copy of the same song', () async {
    final original = await writeFile('original.mp3', [1, 2, 3]);
    final reencoded = await writeFile('reencoded.mp3', [9, 9, 9]); // different bytes -> different hash
    final service = buildService({
      original.path: const TrackTags(title: 'Same Song', durationMs: 200000),
      reencoded.path: const TrackTags(title: 'Same Song', durationMs: 200500),
    });

    final result = await service.importFiles([original, reencoded]);

    expect(result.imported, 1);
    expect(result.skippedDuplicates, 1);
  });

  test('a track that cannot be read is counted as failed, not thrown', () async {
    final missing = File('${tempDir.path}/missing.mp3');
    final service = buildService({});

    final result = await service.importFiles([missing]);

    expect(result.failed, 1);
    expect(result.imported, 0);
  });

  test('cover bytes are cached to disk and referenced by coverPath', () async {
    final file = await writeFile('a.mp3', [1, 2, 3]);
    final service = buildService({
      file.path: TrackTags(title: 'Song A', coverBytes: Uint8List.fromList([10, 20, 30])),
    });

    await service.importFiles([file]);
    final track = (await tracksRepository.all()).single;

    expect(track.coverPath, isNotNull);
    expect(await File(track.coverPath!).readAsBytes(), [10, 20, 30]);
  });
}
