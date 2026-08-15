import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers.dart';
import '../../../data/models/playback_state.dart';
import '../../../services/playback/player_service.dart';
import '../../../services/playback/playback_state_writer.dart';
import '../models/queue_source.dart';

/// Where the current queue came from — set by callers right alongside
/// `playerService.setQueue(...)`; `null` before anything has ever played.
/// See [QueueSource].
final queueSourceProvider = StateProvider<QueueSource?>((ref) => null);

final isPlayingProvider = StreamProvider<bool>(
  (ref) => ref.watch(playerServiceProvider).playingStream,
);

final playbackPositionProvider = StreamProvider<PlaybackPositionState>(
  (ref) => ref.watch(playerServiceProvider).positionStream,
);

final currentTrackProvider = StreamProvider(
  (ref) => ref.watch(playerServiceProvider).currentTrackStream,
);

/// The single synced "last paused here" row for this profile — see
/// [PlaybackStateWriter] (writer side) and
/// docs/adr/0029-playback-state-sync.md.
final playbackStateProvider = StreamProvider<PlaybackState?>(
  (ref) => ref.watch(playbackStateRepositoryProvider).watch(),
);

/// Forced into existence once per session (see `profile_session.dart`,
/// same "read once so its constructor's subscription starts even though
/// nothing else reads this provider" pattern as `pairingServiceProvider`)
/// — writes [playbackStateProvider]'s row on every pause.
final playbackStateWriterProvider = Provider<PlaybackStateWriter>((ref) {
  final writer = PlaybackStateWriter(
    playerService: ref.watch(playerServiceProvider),
    repository: ref.watch(playbackStateRepositoryProvider),
    selfDevice: ref.watch(selfDeviceProvider),
    currentQueueSource: () => ref.read(queueSourceProvider),
  );
  writer.start();
  ref.onDispose(writer.dispose);
  return writer;
});
