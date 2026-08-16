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
    // Loop-the-whole-queue is the default (docs/adr/0031-shuffle-and-repeat.md)
    // — fire-and-forget, nothing downstream waits on this having landed.
    unawaited(_player.setPlaylistMode(PlaylistMode.loop));
    _playlistSub = _player.stream.playlist.listen((playlist) {
      // `playlist-(un)shuffle` (see [setShuffle]) reorders mpv's own
      // playlist in place rather than touching our `_queue` — rebuild it
      // from whatever order mpv now reports, keyed by the `trackId` extra
      // every `Media` carries (set in [setQueue]), so `_queue[index]`
      // below always matches what's actually about to play.
      final reordered = [
        for (final media in playlist.medias)
          if (_tracksById[media.extras?['trackId']] case final track?) track,
      ];
      if (reordered.length == playlist.medias.length && reordered.isNotEmpty) {
        _queue = reordered;
      }
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
  final _shuffleController = StreamController<bool>.broadcast();
  final _repeatModeController = StreamController<PlaybackRepeatMode>.broadcast();
  late final StreamSubscription<Playlist> _playlistSub;
  List<Track> _queue = const [];
  final Map<String, Track> _tracksById = {};
  Track? _currentTrack;
  bool _shuffleEnabled = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.all;

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
  Duration get position => _player.state.position;

  @override
  Stream<bool> get shuffleStream => _shuffleController.stream;

  @override
  Stream<PlaybackRepeatMode> get repeatModeStream => _repeatModeController.stream;

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
    // Tracks known only through synced metadata (file not downloaded to
    // this device yet, see Track.isAvailableLocally) have no path to
    // play — drop them rather than hand mpv a queue it can't open.
    final playable = tracks.where((t) => t.isAvailableLocally).toList();
    _queue = playable;
    _tracksById
      ..clear()
      ..addEntries(playable.map((t) => MapEntry(t.id, t)));

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

    if (seekTo == null) {
      await _player.open(playlist, play: autoPlay);
    } else {
      // Always open paused first, seek, *then* play — opening straight
      // into `play: true` and seeking afterward is audible: a brief
      // moment of the track playing from 0 before the seek lands. See
      // [_seekAfterOpen] for why the seek itself needs retrying rather
      // than a single call.
      await _player.open(playlist, play: false);
      await _seekAfterOpen(seekTo);
      if (autoPlay) await _player.play();
    }
    // `open()` resets mpv's own shuffle flag internally (it clears and
    // reloads the whole native playlist) — reapply ours so the toggle
    // stays sticky across queue changes instead of silently going back
    // to unshuffled every time the user picks a new track/playlist.
    if (_shuffleEnabled) await _player.setShuffle(true);
    _currentTrack = playable[effectiveStart];
    _currentTrackController.add(_currentTrack);
  }

  /// media_kit/libmpv loads media **asynchronously** even after `open()`
  /// itself resolves — a `seek()` issued right after can race mpv's own
  /// in-progress load, which resets position back to 0 once loading
  /// actually finishes, silently discarding the seek (see
  /// docs/adr/0029-playback-state-sync.md, the "restore a saved/synced
  /// playback position" flow this exists for).
  ///
  /// An earlier version of this waited for the *next* `duration` stream
  /// event before seeking — doesn't work: every stream `PlayerStream`
  /// exposes is `.distinct()`-filtered at the source (see media_kit's
  /// `platform_player.dart`), so re-opening a track with the exact same
  /// duration as whatever was playing before — which is the *common*
  /// case here, since "restore a saved position" usually means reopening
  /// the very same track — never re-emits `duration` at all, and the
  /// wait just runs out its timeout every time.
  ///
  /// Verifying against the actually observed position instead sidesteps
  /// that entirely: seek, wait a beat, check how far `_player.state.position`
  /// actually landed from [target]; if mpv's own load-reset raced and won,
  /// it'll show as position snapping back near 0, and the loop just
  /// seeks again. Bounded to ~1.2s total so a track that's somehow never
  /// going to accept the seek doesn't hang the caller.
  Future<void> _seekAfterOpen(Duration target) async {
    if (target <= Duration.zero) return;
    for (var attempt = 0; attempt < 8; attempt++) {
      await _player.seek(target);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if ((_player.state.position - target).abs() < const Duration(milliseconds: 500)) return;
    }
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
  Future<void> setShuffle(bool enabled) async {
    _shuffleEnabled = enabled;
    _shuffleController.add(enabled);
    await _player.setShuffle(enabled);
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _repeatMode = mode;
    _repeatModeController.add(mode);
    await _player.setPlaylistMode(switch (mode) {
      PlaybackRepeatMode.off => PlaylistMode.none,
      PlaybackRepeatMode.all => PlaylistMode.loop,
      PlaybackRepeatMode.one => PlaylistMode.single,
    });
  }

  @override
  Future<void> dispose() async {
    await _playlistSub.cancel();
    await _currentTrackController.close();
    await _shuffleController.close();
    await _repeatModeController.close();
    await _player.dispose();
  }
}
