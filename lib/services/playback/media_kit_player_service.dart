import 'dart:async';

import 'package:media_kit/media_kit.dart' hide Track;

import '../../data/models/track.dart';
import 'player_service.dart';

/// [PlayerService] backed by `package:media_kit` (libmpv).
///
/// Call `MediaKit.ensureInitialized()` once in `main()` before constructing
/// this class.
class MediaKitPlayerService implements PlayerService {
  MediaKitPlayerService() : _player = Player() {
    _playlistSub = _player.stream.playlist.listen((playlist) {
      final index = playlist.index;
      final track = (index >= 0 && index < _queue.length) ? _queue[index] : null;
      if (track != _currentTrack) {
        _currentTrack = track;
        _currentTrackController.add(track);
      }
    });
  }

  final Player _player;
  final _currentTrackController = StreamController<Track?>.broadcast();
  late final StreamSubscription<Playlist> _playlistSub;
  List<Track> _queue = const [];
  Track? _currentTrack;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<PlaybackPositionState> get positionStream => _player.stream.position.map(
        (position) => PlaybackPositionState(
          position: position,
          duration: _player.state.duration,
        ),
      );

  @override
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Track? get currentTrack => _currentTrack;

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    // Tracks known only through synced metadata (file not downloaded to
    // this device yet, see Track.isAvailableLocally) have no path to
    // play — drop them rather than hand mpv a queue it can't open.
    final playable = tracks.where((t) => t.isAvailableLocally).toList();
    _queue = playable;

    if (playable.isEmpty) {
      await _player.stop();
      _currentTrack = null;
      _currentTrackController.add(null);
      return;
    }

    final requestedId = (startIndex >= 0 && startIndex < tracks.length) ? tracks[startIndex].id : null;
    final resolvedStart = requestedId == null ? -1 : playable.indexWhere((t) => t.id == requestedId);
    final effectiveStart = resolvedStart < 0 ? 0 : resolvedStart;

    final playlist = Playlist(
      [for (final track in playable) Media(track.path!, extras: {'trackId': track.id})],
      index: effectiveStart,
    );
    await _player.open(playlist);
    _currentTrack = playable[effectiveStart];
    _currentTrackController.add(_currentTrack);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> next() => _player.next();

  @override
  Future<void> previous() => _player.previous();

  @override
  Future<void> dispose() async {
    await _playlistSub.cancel();
    await _currentTrackController.close();
    await _player.dispose();
  }
}
