import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers.dart';
import '../../../services/playback/player_service.dart';
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
