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

  bool _isPlaying = false;
  Track? _currentTrack;

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
  bool get isPlaying => _isPlaying;

  @override
  Track? get currentTrack => _currentTrack;

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    lastQueue = tracks;
    lastStartIndex = startIndex;
    _currentTrack = tracks.isEmpty ? null : tracks[startIndex];
    _currentTrackController.add(_currentTrack);
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
  Future<void> seek(Duration position) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> dispose() async {
    await _playingController.close();
    await _positionController.close();
    await _currentTrackController.close();
    await _completedController.close();
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
