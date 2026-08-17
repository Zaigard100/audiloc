import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';
import '../../../services/playback/player_service.dart';
import '../../devices/providers/remote_control_providers.dart';
import 'player_providers.dart';
import 'playback_ownership_providers.dart';

/// Talks to whichever device currently owns playback — this device's
/// own `playerServiceProvider`, or a remote device via
/// `RemoteControlController`/`Client` (ADR 0030's existing live
/// channel), based on [activePlaybackTargetProvider]. Used by the full
/// player screen and every "tap a track to play it" list (library,
/// favorites, playlists, search) — picking a track while another
/// device owns playback sends it there instead of silently stealing
/// ownership back to this device. Keyboard shortcuts,
/// `PlaybackStateWriter`, and incoming remote control from another
/// device keep talking to `playerServiceProvider` directly — those are
/// about *this device's own* engine specifically, not "whichever device
/// is active" (see docs/adr/0033-playback-ownership-and-handoff.md).
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

  /// Backs every "tap a track to play it" list — replaces every
  /// `playerServiceProvider.setQueue(...)` call site that used to play
  /// unconditionally on this device regardless of who currently owns
  /// playback. Remote mode sends the whole tapped list via the existing
  /// `loadAndPlay` (ADR 0030), starting at [startIndex], from position
  /// zero — there's no "current position" to preserve, this is a fresh
  /// selection, not a resume.
  Future<void> playQueue(List<Track> tracks, {required int startIndex}) async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).setQueue(tracks, startIndex: startIndex);
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).loadAndPlay(
              tracks.map((t) => t.id).toList(),
              startIndex,
              Duration.zero,
            );
    }
  }

  Future<void> setShuffle(bool enabled) async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).setShuffle(enabled);
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).setShuffle(enabled);
    }
  }

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    switch (_target) {
      case LocalPlaybackTarget():
        await _ref.read(playerServiceProvider).setRepeatMode(mode);
      case RemotePlaybackTarget(:final deviceId):
        _ref.read(remoteControlControllerProvider(deviceId)).setRepeatMode(mode.name);
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

final activePlaybackShuffleEnabledProvider = Provider<bool>((ref) {
  final target = ref.watch(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();
  return switch (target) {
    LocalPlaybackTarget() => ref.watch(shuffleEnabledProvider).value ?? false,
    RemotePlaybackTarget(:final deviceId) =>
      ref.watch(remoteControlConnectionProvider(deviceId)).value?.state?.shuffleEnabled ?? false,
  };
});

final activePlaybackRepeatModeProvider = Provider<PlaybackRepeatMode>((ref) {
  final target = ref.watch(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();
  switch (target) {
    case LocalPlaybackTarget():
      return ref.watch(repeatModeProvider).value ?? PlaybackRepeatMode.all;
    case RemotePlaybackTarget(:final deviceId):
      final modeName = ref.watch(remoteControlConnectionProvider(deviceId)).value?.state?.repeatMode;
      return PlaybackRepeatMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => PlaybackRepeatMode.all,
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
      // `Stream.value(ref.watch(currentTrackProvider).value)`, not a
      // fresh `playerServiceProvider.currentTrackStream` watch — this
      // provider rebuilds every time `activePlaybackTargetProvider`
      // does (even when the resolved target doesn't actually change,
      // e.g. its own upstream `profileSyncEnabledProvider` merely
      // finishing its first CRDT load), and re-subscribing directly to
      // the *raw* engine stream on every rebuild loses whatever was
      // emitted between the old subscription tearing down and the new
      // one attaching — `currentTrackController` is a plain broadcast
      // `StreamController` with no replay. Reading the already-stable,
      // continuously-subscribed `currentTrackProvider`'s current
      // `.value` instead (same fix `activePlaybackIsPlayingProvider`/
      // `activePlaybackPositionProvider` already apply) can't ever miss
      // an update: a fresh rebuild here is itself only triggered when
      // that value actually changes, so it's always read up to date.
      return Stream.value(ref.watch(currentTrackProvider).value);
    case RemotePlaybackTarget(:final deviceId):
      final trackId = ref.watch(remoteControlConnectionProvider(deviceId)).value?.state?.trackId;
      if (trackId == null) return Stream.value(null);
      return Stream.fromFuture(ref.watch(tracksRepositoryProvider).byId(trackId));
  }
});
