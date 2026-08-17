import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../providers/active_playback_controller.dart';

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

    // Ownership-aware (docs/adr/0033-playback-ownership-and-handoff.md) —
    // controls whichever device currently owns playback, same as the
    // full player screen/mini player, not just this device's own local
    // engine.
    final controller = ref.watch(activePlaybackControllerProvider);
    final step = Duration(seconds: settings.seekStepSeconds);

    void seekBy(Duration delta) {
      if (ref.read(activePlaybackCurrentTrackProvider).value == null) return;
      final target = ref.read(activePlaybackPositionProvider).position + delta;
      controller.seek(target < Duration.zero ? Duration.zero : target);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): controller.playOrPause,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): controller.playOrPause,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(step),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-step),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): controller.next,
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): controller.previous,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
