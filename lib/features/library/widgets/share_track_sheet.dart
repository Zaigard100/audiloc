import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../devices/providers/devices_providers.dart';

/// Sends [track] (or, if the user opts in, every track sharing its
/// album+artist) to a device picked from whoever's currently visible on
/// the LAN — paired or not, any profile. See
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md: this is the
/// replacement for pairing itself moving content between profiles.
Future<void> showShareTrackSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => _ShareTrackSheet(track: track),
  );
}

class _ShareTrackSheet extends ConsumerStatefulWidget {
  const _ShareTrackSheet({required this.track});

  final Track track;

  @override
  ConsumerState<_ShareTrackSheet> createState() => _ShareTrackSheetState();
}

class _ShareTrackSheetState extends ConsumerState<_ShareTrackSheet> {
  var _shareWholeAlbum = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final hasAlbum = track.album != null && track.album!.trim().isNotEmpty;
    final nearby = (ref.watch(nearbyPeersProvider).value ?? const {}).values.toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAlbum)
            SwitchListTile(
              title: const Text('Поделиться всем альбомом'),
              subtitle: Text(track.displayAlbum),
              value: _shareWholeAlbum,
              onChanged: (value) => setState(() => _shareWholeAlbum = value),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Устройства поблизости', style: TextStyle(color: AppTheme.onSurfaceMuted)),
            ),
          ),
          if (nearby.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Text('Поблизости не найдено ни одного устройства'),
            )
          else
            for (final peer in nearby)
              ListTile(
                leading: const Icon(Icons.devices_other),
                title: Text(peer.name),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final shareService = ref.read(shareServiceProvider);
                  if (_shareWholeAlbum) {
                    final all = await ref.read(tracksRepositoryProvider).all();
                    final albumTracks =
                        all.where((t) => t.album == track.album && t.artist == track.artist).toList();
                    await shareService.shareAlbum(host: peer.host, port: sharePort, tracks: albumTracks);
                  } else {
                    await shareService.shareTrack(host: peer.host, port: sharePort, track: track);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                  messenger.showSnackBar(SnackBar(content: Text('Отправлено «${peer.name}»')));
                },
              ),
        ],
      ),
    );
  }
}
