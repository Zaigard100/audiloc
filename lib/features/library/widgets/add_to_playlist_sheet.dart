import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';
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
    return SafeArea(
      child: playlistsAsync.when(
        data: (playlists) => playlists.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Нет ни одного плейлиста — создайте его на вкладке «Плейлисты»'),
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
                              .showSnackBar(SnackBar(content: Text('Добавлено в «${playlist.name}»')));
                        }
                      },
                    ),
                ],
              ),
        loading: () =>
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        error: (error, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Ошибка: $error')),
      ),
    );
  }
}
