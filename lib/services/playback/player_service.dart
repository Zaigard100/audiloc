import '../../data/models/track.dart';

/// How the queue behaves once it runs out (or, for [one], on every track):
/// [off] stops after the last track, [all] wraps back to the first track
/// (default — see docs/adr/0031-shuffle-and-repeat.md), [one] repeats the
/// current track indefinitely. Mirrors `media_kit`'s `PlaylistMode`
/// one-to-one, kept as our own enum so the UI/provider layer never needs
/// to import `media_kit` (see the class doc below).
enum PlaybackRepeatMode { off, all, one }

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
  Stream<bool> get shuffleStream;
  Stream<PlaybackRepeatMode> get repeatModeStream;

  bool get isPlaying;
  Track? get currentTrack;
  bool get isShuffleEnabled;
  PlaybackRepeatMode get repeatMode;

  /// Synchronous snapshot of the current position — unlike
  /// [positionStream], usable at a single point in time (e.g. the moment
  /// playback pauses, to persist a resume point — see
  /// docs/adr/0029-playback-state-sync.md) without needing to be
  /// mid-subscription.
  Duration get position;

  /// Synchronous snapshot of the whole current queue, in play order —
  /// used to let another device pull the *whole* queue back from this
  /// one (docs/adr/0033-playback-ownership-and-handoff.md), not just
  /// the single current track, which would leave that device's own
  /// next/previous with nothing to move to (the same regression ADR
  /// 0030 already fixed once for the forward handoff direction).
  List<Track> get queue;

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

  /// Randomizes play order within the current queue (library/playlist,
  /// whatever it was set from) rather than reordering the queue itself —
  /// `next`/`previous` then walk that random order. Sticky across
  /// `next`/`previous`, but a fresh `setQueue` call needs it reapplied
  /// (see `MediaKitPlayerService.setQueue`'s doc).
  Future<void> setShuffle(bool enabled);

  Future<void> setRepeatMode(PlaybackRepeatMode mode);

  Future<void> dispose();
}
