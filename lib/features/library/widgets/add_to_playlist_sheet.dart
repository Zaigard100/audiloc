import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';
import '../../../l10n/l10n.dart';
import '../../playlists/providers/playlists_providers.dart';

/// Picks which of the user's playlists [track] should be added to.
Future<void> showAddToPlaylistSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => _AddToPlaylistSheet(track: track),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final l10n = context.l10n;
    return SafeArea(
      child: playlistsAsync.when(
        data: (playlists) => playlists.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.noPlaylistsYet),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final playlist in playlists)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(playlist.name),
                      onTap: () async {
                        await ref.read(playlistsRepositoryProvider).addTrack(playlist.id, track.id);
                        if (context.mounted) Navigator.of(context).pop();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(l10n.addedToPlaylistSnackbar(playlist.name))));
                        }
                      },
                    ),
                ],
              ),
        loading: () =>
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        error: (error, _) => Padding(padding: const EdgeInsets.all(16), child: Text(l10n.commonErrorPrefix(error))),
      ),
    );
  }
}
