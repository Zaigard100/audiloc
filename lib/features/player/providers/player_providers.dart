import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../services/playback/player_service.dart';

final isPlayingProvider = StreamProvider<bool>(
  (ref) => ref.watch(playerServiceProvider).playingStream,
);

final playbackPositionProvider = StreamProvider<PlaybackPositionState>(
  (ref) => ref.watch(playerServiceProvider).positionStream,
);

final currentTrackProvider = StreamProvider(
  (ref) => ref.watch(playerServiceProvider).currentTrackStream,
);
