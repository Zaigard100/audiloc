import 'package:path/path.dart' as p;

/// A single audio file in the local library.
///
/// [id] is the SHA-256 hash of the file contents (see
/// `services/library_import`), so re-importing the same bytes from a
/// different path or on a different device naturally deduplicates.
class Track {
  const Track({
    required this.id,
    required this.path,
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs,
    this.bitrateKbps,
    this.coverPath,
    this.fileSize,
    this.addedOnDevice,
  });

  final String id;
  final String path;
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? durationMs;
  final int? bitrateKbps;
  final String? coverPath;
  final int? fileSize;
  final String? addedOnDevice;

  Duration get duration => Duration(milliseconds: durationMs ?? 0);

  /// Falls back to the file name when no tag title is available.
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return p.basenameWithoutExtension(path);
  }

  String get displayArtist {
    final a = artist?.trim();
    return (a != null && a.isNotEmpty) ? a : 'Неизвестный исполнитель';
  }

  String get displayAlbum {
    final a = album?.trim();
    return (a != null && a.isNotEmpty) ? a : 'Неизвестный альбом';
  }

  factory Track.fromRow(Map<String, Object?> row) => Track(
        id: row['id']! as String,
        path: row['path']! as String,
        title: row['title'] as String?,
        artist: row['artist'] as String?,
        album: row['album'] as String?,
        genre: row['genre'] as String?,
        durationMs: row['duration_ms'] as int?,
        bitrateKbps: row['bitrate_kbps'] as int?,
        coverPath: row['cover_path'] as String?,
        fileSize: row['file_size'] as int?,
        addedOnDevice: row['added_on_device'] as String?,
      );

  Track copyWith({
    String? path,
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? durationMs,
    int? bitrateKbps,
    String? coverPath,
    int? fileSize,
    String? addedOnDevice,
  }) =>
      Track(
        id: id,
        path: path ?? this.path,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        genre: genre ?? this.genre,
        durationMs: durationMs ?? this.durationMs,
        bitrateKbps: bitrateKbps ?? this.bitrateKbps,
        coverPath: coverPath ?? this.coverPath,
        fileSize: fileSize ?? this.fileSize,
        addedOnDevice: addedOnDevice ?? this.addedOnDevice,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
