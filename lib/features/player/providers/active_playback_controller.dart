import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';
import '../../../services/playback/player_service.dart';
import '../../devices/providers/remote_control_providers.dart';
import 'player_providers.dart';
import 'playback_ownership_providers.dart';

/// Talks to whichever device the full player screen should currently
/// control — this device's own `playerServiceProvider`, or a remote
/// device via `RemoteControlController`/`Client` (ADR 0030's existing
/// live channel), based on [activePlaybackTargetProvider]. Used **only**
/// by `full_player_screen.dart` — every other reader in the app (mini
/// player, keyboard shortcuts, `PlaybackStateWriter`, incoming remote
/// control from another device) keeps talking to `playerServiceProvider`
/// directly, unaffected by which device the player screen happens to be
/// showing. See docs/adr/0033-playback-ownership-and-handoff.md.
class ActivePlaybackController {
  ActivePlaybackController(this._ref);
  final Ref _ref;

  ActivePlaybackTarget get _target =>
      _ref.read(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();

  Future<void> play() async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).play();
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).play();
    }
  }

  Future<void> pause() async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).pause();
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).pause();
    }
  }

  /// Remote mode has no `playOrPause` on the wire (ADR 0030) — resolved
  /// here from the last-known pushed `RemoteState.isPlaying` instead.
  Future<void> playOrPause() async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).playOrPause();
      case RemotePlaybackTarget(:final deviceId):
        final isPlaying =
            _ref.read(remoteControlConnectionProvider(deviceId)).value?.state?.isPlaying ?? false;
        final controller = _ref.read(remoteControlControllerProvider(deviceId));
        if (isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
    }
  }

  Future<void> seek(Duration position) async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).seek(position);
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).seek(position);
    }
  }

  Future<void> next() async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).next();
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).next();
    }
  }

  Future<void> previous() async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).previous();
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).previous();
    }
  }
}

final activePlaybackControllerProvider =
    Provider<ActivePlaybackController>((ref) => ActivePlaybackController(ref));

/// Plain (not Stream) providers, not family-parameterized — each simply
/// re-derives from [activePlaybackTargetProvider] plus whichever
/// underlying provider is relevant, so `full_player_screen.dart` doesn't
/// need to branch on the target itself for every value it displays.
final activePlaybackIsPlayingProvider = Provider<bool>((ref) {
  final target = ref.watch(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();
  return switch (target) {
    LocalPlaybackTarget() => ref.watch(isPlayingProvider).value ?? false,
    RemotePlaybackTarget(:final deviceId) =>
      ref.watch(remoteControlConnectionProvider(deviceId)).value?.state?.isPlaying ?? false,
  };
});

final activePlaybackPositionProvider = Provider<PlaybackPositionState>((ref) {
  final target = ref.watch(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();
  switch (target) {
    case LocalPlaybackTarget():
      return ref.watch(playbackPositionProvider).value ??
          const PlaybackPositionState(position: Duration.zero, duration: Duration.zero);
    case RemotePlaybackTarget(:final deviceId):
      final state = ref.watch(remoteControlConnectionProvider(deviceId)).value?.state;
      return PlaybackPositionState(
        position: Duration(milliseconds: state?.positionMs ?? 0),
        duration: Duration(milliseconds: state?.durationMs ?? 0),
      );
  }
});

/// Remote mode resolves the full `Track` (for cover art / favorite
/// toggle) from the synced `tracks` table by id — `RemoteState` itself
/// only carries `trackId`/`title`/`artist` as a fallback for the rare
/// case this device hasn't synced that track's metadata at all.
final activePlaybackCurrentTrackProvider = StreamProvider<Track?>((ref) {
  final target = ref.watch(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();
  switch (target) {
    case LocalPlaybackTarget():
      return ref.watch(playerServiceProvider).currentTrackStream;
    case RemotePlaybackTarget(:final deviceId):
      final trackId = ref.watch(remoteControlConnectionProvider(deviceId)).value?.state?.trackId;
      if (trackId == null) return Stream.value(null);
      return Stream.fromFuture(ref.watch(tracksRepositoryProvider).byId(trackId));
  }
});
