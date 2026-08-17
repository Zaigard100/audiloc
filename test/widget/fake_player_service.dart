import 'dart:async';

import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/services/playback/player_service.dart';

/// In-memory [PlayerService] double, so widget tests never touch
/// `media_kit` (which needs native libmpv bindings unavailable under
/// `flutter test`).
class FakePlayerService implements PlayerService {
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<PlaybackPositionState>.broadcast();
  final _currentTrackController = StreamController<Track?>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _shuffleController = StreamController<bool>.broadcast();
  final _repeatModeController = StreamController<PlaybackRepeatMode>.broadcast();

  bool _isPlaying = false;
  Track? _currentTrack;
  Duration _position = Duration.zero;
  bool _shuffleEnabled = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.all;

  List<Track> lastQueue = [];
  int? lastStartIndex;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<PlaybackPositionState> get positionStream => _positionController.stream;

  @override
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<bool> get shuffleStream => _shuffleController.stream;

  @override
  Stream<PlaybackRepeatMode> get repeatModeStream => _repeatModeController.stream;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Track? get currentTrack => _currentTrack;

  @override
  Duration get position => _position;

  @override
  List<Track> get queue => lastQueue;

  @override
  bool get isShuffleEnabled => _shuffleEnabled;

  @override
  PlaybackRepeatMode get repeatMode => _repeatMode;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool autoPlay = true,
    Duration? seekTo,
  }) async {
    lastQueue = tracks;
    lastStartIndex = startIndex;
    _currentTrack = tracks.isEmpty ? null : tracks[startIndex];
    _position = seekTo ?? Duration.zero;
    _currentTrackController.add(_currentTrack);
    if (autoPlay) await play();
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> playOrPause() => _isPlaying ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    _position = position;
  }

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> setShuffle(bool enabled) async {
    _shuffleEnabled = enabled;
    _shuffleController.add(enabled);
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _repeatMode = mode;
    _repeatModeController.add(mode);
  }

  @override
  Future<void> dispose() async {
    await _playingController.close();
    await _positionController.close();
    await _currentTrackController.close();
    await _completedController.close();
    await _shuffleController.close();
    await _repeatModeController.close();
  }

  void emitTrack(Track? track) {
    _currentTrack = track;
    _currentTrackController.add(track);
  }

  void emitPlaying(bool playing) {
    _isPlaying = playing;
    _playingController.add(playing);
  }

  void emitPosition(PlaybackPositionState state) => _positionController.add(state);
}
