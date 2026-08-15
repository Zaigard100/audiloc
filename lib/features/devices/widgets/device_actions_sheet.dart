import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/device.dart';
import '../../../l10n/l10n.dart';
import '../providers/remote_control_providers.dart';
import 'remote_track_picker_sheet.dart';

/// Long-press (or right-click on desktop) menu on a [DeviceTile] once it's
/// confirmed to allow remote control — see
/// docs/adr/0030-remote-playback-control.md.
Future<void> showDeviceActionsSheet(BuildContext context, WidgetRef ref, Device device) {
  final l10n = context.l10n;
  // `playerService.currentTrack`/`.position`, not `ref.read(currentTrackProvider)`
  // — the latter goes through a `StreamProvider` Riverpod 3 pauses while
  // nothing's actively watching it, which can read back stale/null even
  // when something really is loaded (see docs/adr/0029-playback-state-sync.md's
  // `hasLocalTrack` fix for the exact same pitfall).
  final playerService = ref.read(playerServiceProvider);
  final currentTrack = playerService.currentTrack;
  final controller = ref.read(remoteControlControllerProvider(device.id));

  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(l10n.deviceActionResumeHere),
            enabled: currentTrack != null,
            subtitle: currentTrack == null ? Text(l10n.deviceActionNothingLoaded) : Text(currentTrack.displayTitle),
            onTap: currentTrack == null
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    controller.loadAndPlay(currentTrack.id, playerService.position);
                  },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_outlined),
            title: Text(l10n.deviceActionPickTrack),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showRemoteTrackPickerSheet(context, device.id);
            },
          ),
        ],
      ),
    ),
  );
}
