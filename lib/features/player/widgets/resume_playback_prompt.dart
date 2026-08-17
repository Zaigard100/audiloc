import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/playback_state.dart';
import '../../../data/models/track.dart';
import '../models/queue_source.dart';
import '../providers/player_providers.dart';
import '../providers/queue_resolution.dart';

/// Reacts to [playbackStateProvider] — the *cross-device* sync half of
/// docs/adr/0029-playback-state-sync.md. Restoring this device's own
/// last session after its own restart is a separate, purely local
/// mechanism now (`local_session_restore.dart`,
/// `LocalPlaybackStateStore`) — this function only ever concerns itself
/// with a row written by a genuinely *different* device, gated by the
/// "принимать" setting:
/// - Nothing loaded locally yet — silently apply, paused, ready to
///   resume with a tap.
/// - Something's already loaded here (playing or paused) — left alone
///   entirely. This used to show a "Продолжить с «Трек», 0:30,
///   Устройство?" `SnackBar`, removed at the user's explicit request
///   once the live ownership protocol (docs/adr/0033-playback-ownership-and-handoff.md)
///   made it redundant/confusing alongside explicit handoff — "who's
///   playing" is now always visible and controllable directly, not
///   something to be asked about from a lagged bookmark.
Future<void> handleIncomingPlaybackState(WidgetRef ref, PlaybackState state) async {
  final self = ref.read(selfDeviceProvider);
  // Our own writes never need acting on here — restoring this device's
  // own last session is `local_session_restore.dart`'s job now, entirely
  // independent of whether cross-device sync is even on.
  if (state.deviceId == self.id) return;

  // The unified profile-wide sync toggle — a one-shot CRDT read, not
  // `ref.read(profileSyncEnabledProvider).value`: this runs from a
  // `fireImmediately: true` listener that can fire before that
  // `StreamProvider`'s underlying CRDT watch has delivered its first
  // emission, which would otherwise read as `null`/false and silently
  // drop an incoming state even when sync is actually on.
  if (!await ref.read(profileSettingsRepositoryProvider).isSyncPlaybackEnabled()) return;

  // `playerService.currentTrack` (a plain synchronous getter), not
  // `ref.read(currentTrackProvider).value` — the latter goes through a
  // `StreamProvider`, which Riverpod 3 pauses while nothing's actively
  // watching it; relying on it here would risk a false "nothing loaded"
  // reading right at the moment this function needs the real answer,
  // silently overwriting whatever's actually already playing instead of
  // asking first. The player's own field reflects reality regardless of
  // whether any widget happens to be watching it.
  final hasLocalTrack = ref.read(playerServiceProvider).currentTrack != null;

  // The "sync order" tracks -> playlists -> playback state the ТЗ asked
  // for isn't a transport-level thing `crdt_sync` actually exposes (one
  // merge call already writes every table in a changeset together, see
  // the ADR) — what actually matters, and what this *is*, is a
  // resolvability gate: a playback_state row is only actionable once
  // its referenced track (and playlist, if any) already exist locally.
  // If they don't (yet), silently do nothing rather than resume into a
  // half-known state — nothing about this row changes again on its own,
  // but in practice the reference and its target always arrive in the
  // same merge, so this is a safety net, not the primary mechanism.
  final resolved = await resolvePlaybackStateQueue(
    ref,
    queueType: state.queueType,
    playlistId: state.playlistId,
    trackId: state.trackId,
  );
  if (resolved == null) return;
  final (tracks, startIndex, source) = resolved;

  // Something's already loaded here — leave it alone entirely, no
  // prompt (see this function's doc for why the old SnackBar is gone).
  if (hasLocalTrack) return;

  await _applyResume(ref, tracks, startIndex, source, state, autoPlay: false);
}

Future<void> _applyResume(
  WidgetRef ref,
  List<Track> tracks,
  int startIndex,
  QueueSource source,
  PlaybackState state, {
  required bool autoPlay,
}) async {
  final playerService = ref.read(playerServiceProvider);
  // `seekTo` (not a separate `seek()` call after `setQueue`) — a plain
  // follow-up `seek()` raced the engine's own asynchronous media loading
  // and silently lost, always landing back at 0. See
  // `MediaKitPlayerService.setQueue`'s doc.
  await playerService.setQueue(tracks, startIndex: startIndex, autoPlay: autoPlay, seekTo: state.position);
  ref.read(queueSourceProvider.notifier).state = source;
}
