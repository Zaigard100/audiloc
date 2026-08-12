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

  /// Replaces the queue and starts playing at [startIndex].
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0});

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();

  Future<void> dispose();
}
