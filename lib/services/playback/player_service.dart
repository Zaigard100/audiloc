import '../../data/models/track.dart';

class PlaybackPositionState {
  const PlaybackPositionState({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  double get fraction =>
      duration.inMilliseconds == 0 ? 0 : position.inMilliseconds / duration.inMilliseconds;
}

/// Abstraction over the audio engine so the UI and providers never touch
/// `media_kit` directly. This is what makes widget tests possible without
/// the native libmpv libraries: tests provide a fake implementation instead.
abstract class PlayerService {
  Stream<bool> get playingStream;
  Stream<PlaybackPositionState> get positionStream;
  Stream<Track?> get currentTrackStream;
  Stream<bool> get completedStream;

  bool get isPlaying;
  Track? get currentTrack;

  /// Synchronous snapshot of the current position — unlike
  /// [positionStream], usable at a single point in time (e.g. the moment
  /// playback pauses, to persist a resume point — see
  /// docs/adr/0029-playback-state-sync.md) without needing to be
  /// mid-subscription.
  Duration get position;

  /// Replaces the queue, cued to [startIndex]. Plays immediately unless
  /// [autoPlay] is `false` — used when restoring a synced/persisted
  /// playback position (docs/adr/0029-playback-state-sync.md), which
  /// should land paused exactly where it left off, not immediately start
  /// making sound.
  ///
  /// [seekTo], when given, is where playback should actually start from
  /// (also for the resume flow) — handled here rather than via a
  /// separate external `seek()` call right after, because a plain
  /// `seek()` issued immediately after this returns can race the
  /// engine's own asynchronous media loading and silently lose the seek
  /// once loading finishes (see `MediaKitPlayerService.setQueue`'s doc).
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0, bool autoPlay = true, Duration? seekTo});

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();

  Future<void> dispose();
}
