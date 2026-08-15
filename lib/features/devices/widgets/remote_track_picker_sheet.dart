import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';
import '../../../l10n/l10n.dart';
import '../providers/remote_control_providers.dart';

/// Lists tracks this profile has, filtered to ones the *target* device
/// (`deviceId`) actually has a local copy of — offering one it doesn't
/// have would just fail with `track_not_available` instead of playing.
/// See docs/adr/0030-remote-playback-control.md.
Future<void> showRemoteTrackPickerSheet(BuildContext context, String deviceId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RemoteTrackPickerSheet(deviceId: deviceId),
  );
}

final _tracksAvailableOnDeviceProvider = FutureProvider.autoDispose.family<List<Track>, String>(
  (ref, deviceId) => ref.watch(tracksRepositoryProvider).availableOnDevice(deviceId),
);

class _RemoteTrackPickerSheet extends ConsumerWidget {
  const _RemoteTrackPickerSheet({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tracksAsync = ref.watch(_tracksAvailableOnDeviceProvider(deviceId));

    return DraggableScrollableSheet(
      expand: false,
      builder: (context, scrollController) => tracksAsync.when(
        data: (tracks) => tracks.isEmpty
            ? Center(child: Text(l10n.deviceActionNoTracksAvailable))
            : ListView.builder(
                controller: scrollController,
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return ListTile(
                    title: Text(track.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(track.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.of(context).pop();
                      ref
                          .read(remoteControlControllerProvider(deviceId))
                          .loadAndPlay(track.id, Duration.zero);
                    },
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonErrorPrefix(error))),
      ),
    );
  }
}
