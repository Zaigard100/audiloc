import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/playlist.dart';
import 'playlist_cover_picker.dart';

/// Long-press (or right-click on desktop) action menu for a user-created
/// playlist — never shown for the built-in "Избранное"/"Удалённые" cards.
/// `PlaylistsRepository.rename()`/`.delete()` already existed; this is
/// purely the missing UI for them, plus the new cover picker (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md).
Future<void> showPlaylistActionsSheet(BuildContext context, WidgetRef ref, Playlist playlist) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Переименовать'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _renameDialog(context, ref, playlist);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Выбрать обложку'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showPlaylistCoverPicker(context, ref, playlist);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Удалить'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _confirmDelete(context, ref, playlist);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _renameDialog(BuildContext context, WidgetRef ref, Playlist playlist) async {
  final controller = TextEditingController(text: playlist.name);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Переименовать плейлист'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty || name == playlist.name) return;
  await ref.read(playlistsRepositoryProvider).rename(playlist.id, name);
}

Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Playlist playlist) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Удалить плейлист?'),
      content: Text('«${playlist.name}» будет удалён. Сами треки в библиотеке останутся нетронутыми.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Удалить')),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(playlistsRepositoryProvider).delete(playlist.id);
}
