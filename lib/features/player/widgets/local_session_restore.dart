import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../providers/player_providers.dart';
import '../providers/queue_resolution.dart';

/// Restores this device's own last-paused track/position after its own
/// restart — the purely local half of docs/adr/0029-playback-state-sync.md,
/// entirely independent of the "отправлять"/"принимать" cross-device sync
/// toggles (`resume_playback_prompt.dart`). Called once, from
/// `AppShell.initState()`, right alongside (and typically resolving
/// before) that cross-device listener — if a genuinely incoming
/// cross-device update also arrives shortly after, it'll correctly see
/// something already loaded here and ask before overwriting it, same as
/// always.
///
/// Always silent — no dialog/snackbar needed: at the point this runs
/// (session startup), nothing else could plausibly already be loaded to
/// conflict with, unlike the cross-device case.
Future<void> restoreLocalSession(WidgetRef ref) async {
  if (!ref.read(currentSaveLocalSessionProvider)) return;

  final state = await ref.read(localPlaybackStateStoreProvider).read();
  if (state == null) return;

  final resolved = await resolvePlaybackStateQueue(
    ref,
    queueType: state.queueType,
    playlistId: state.playlistId,
    trackId: state.trackId,
  );
  if (resolved == null) return;
  final (tracks, startIndex, source) = resolved;

  final playerService = ref.read(playerServiceProvider);
  // Never re-loaded once already something's playing (e.g. the user
  // tapped a track while this was still resolving) — a plain guard, not
  // a hard requirement, since this whole function only ever runs once
  // per session right at startup.
  if (playerService.currentTrack != null) return;

  await playerService.setQueue(tracks, startIndex: startIndex, autoPlay: false, seekTo: state.position);
  ref.read(queueSourceProvider.notifier).state = source;
}
