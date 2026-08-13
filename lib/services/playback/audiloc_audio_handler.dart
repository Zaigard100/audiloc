import 'package:audio_service/audio_service.dart';

import '../../data/models/track.dart';
import 'player_service.dart';

/// Mirrors [PlayerService] into the OS media session — notification/lock
/// screen controls and headset buttons (ТЗ п.3) — without the rest of the
/// app changing how it talks to playback. The UI keeps using
/// [PlayerService] directly; this only *also* broadcasts its state
/// outward and relays commands that arrive from outside the app (a
/// notification tap, a headset click) back into the same instance.
///
/// Android-only — see `main.dart` for the `Platform.isAndroid` gate. Only
/// Android/iOS/macOS/web have a real `audio_service` platform
/// implementation (Linux would need the separate `audio_service_mpris`
/// package, not something this ТЗ asked for); calling `AudioService.init`
/// on a platform without one throws.
class AudilocAudioHandler extends BaseAudioHandler with SeekHandler {
  AudilocAudioHandler(this._player) {
    _player.positionStream.listen((state) => _lastPosition = state.position);
    _player.playingStream.listen((_) => _broadcastPlaybackState());
    _player.currentTrackStream.listen((track) {
      _lastPosition = Duration.zero;
      _broadcastMediaItem(track);
      _broadcastPlaybackState();
    });
    _broadcastMediaItem(_player.currentTrack);
    _broadcastPlaybackState();
  }

  final PlayerService _player;
  Duration _lastPosition = Duration.zero;

  void _broadcastMediaItem(Track? track) {
    mediaItem.add(track == null
        ? null
        : MediaItem(
            id: track.id,
            title: track.displayTitle,
            artist: track.displayArtist,
            album: track.displayAlbum,
            duration: track.durationMs == null ? null : Duration(milliseconds: track.durationMs!),
            artUri: track.coverPath == null ? null : Uri.file(track.coverPath!),
          ));
  }

  void _broadcastPlaybackState() {
    final playing = _player.isPlaying;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      playing: playing,
      updatePosition: _lastPosition,
      processingState: AudioProcessingState.ready,
    ));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> stop() async {
    await _player.pause();
    await super.stop();
  }
}
