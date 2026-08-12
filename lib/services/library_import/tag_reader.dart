import 'dart:typed_data';

import 'package:audiotags/audiotags.dart' as audiotags;

class TrackTags {
  const TrackTags({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs,
    this.coverBytes,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? durationMs;
  final Uint8List? coverBytes;
}

/// Thin wrapper around `package:audiotags` (lofty-rs under the hood).
///
/// ТЗ names `id3` for this job, but that package has been unmaintained
/// since 2021 and only ever covered MP3 — see
/// docs/adr/0002-audiotags-instead-of-id3.md.
class TagReader {
  Future<TrackTags?> read(String path) async {
    final tag = await audiotags.AudioTags.read(path);
    if (tag == null) return null;
    return TrackTags(
      title: _nullIfBlank(tag.title),
      artist: _nullIfBlank(tag.trackArtist),
      album: _nullIfBlank(tag.album),
      genre: _nullIfBlank(tag.genre),
      // lofty-rs reports whole-second durations; converted to ms for
      // consistency with the rest of the app. This is only used as a
      // best-effort value before playback starts — media_kit reports the
      // authoritative duration once a track is actually opened.
      durationMs: tag.duration == null ? null : tag.duration! * 1000,
      coverBytes: tag.pictures.isNotEmpty ? tag.pictures.first.bytes : null,
    );
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
