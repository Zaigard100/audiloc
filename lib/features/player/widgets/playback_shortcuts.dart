import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Wraps [child] with keyboard playback controls — Space to play/pause,
/// Left/Right arrows to seek back/forward by the configured step, plus
/// the dedicated hardware media keys many keyboards have
/// (play/pause/next/previous). See docs/adr/0029-playback-state-sync.md.
///
/// Only fires while the AudiLoc window itself has OS focus — Flutter key
/// events never reach an unfocused window at all, and there's no
/// cross-platform way around that without a native background/global
/// media-key integration this pass doesn't add (Linux would need MPRIS,
/// Windows would need System Media Transport Controls — real, distinct
/// undertakings from "handle the keys Flutter already gets"). Android
/// already gets the "works even when not focused" behavior for free,
/// through a completely different mechanism —
/// `AudilocAudioHandler`/`audio_service` relaying Bluetooth/headset and
/// lock-screen media buttons via the OS media session, regardless of
/// whether AudiLoc's own window/activity is focused.
///
/// A focused `TextField` (search, a rename dialog, ...) still gets these
/// keys *first* — `CallbackShortcuts` only fires for events a descendant
/// left unhandled, and normal text editing already consumes Space/arrow
/// keys for typing and cursor movement, so this never fights with
/// typing.
class PlaybackShortcuts extends ConsumerWidget {
  const PlaybackShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentPlaybackShortcutsSettingsProvider);
    if (!settings.enabled) return child;

    final playerService = ref.watch(playerServiceProvider);
    final step = Duration(seconds: settings.seekStepSeconds);

    void seekBy(Duration delta) {
      if (playerService.currentTrack == null) return;
      final target = playerService.position + delta;
      playerService.seek(target < Duration.zero ? Duration.zero : target);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): playerService.playOrPause,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): playerService.playOrPause,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(step),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-step),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): playerService.next,
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): playerService.previous,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
