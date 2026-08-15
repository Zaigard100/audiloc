import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/playlist.dart';
import '../../../l10n/l10n.dart';
import 'playlist_cover_picker.dart';

/// Long-press (or right-click on desktop) action menu for a user-created
/// playlist — never shown for the built-in "Избранное"/"Удалённые" cards.
/// `PlaylistsRepository.rename()`/`.delete()` already existed; this is
/// purely the missing UI for them, plus the new cover picker (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md).
Future<void> showPlaylistActionsSheet(BuildContext context, WidgetRef ref, Playlist playlist) {
  final l10n = context.l10n;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.playlistActionRename),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _renameDialog(context, ref, playlist);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.playlistActionPickCover),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showPlaylistCoverPicker(context, ref, playlist);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.commonDelete),
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
  final l10n = context.l10n;
  final controller = TextEditingController(text: playlist.name);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.playlistRenameTitle),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.commonCancel)),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty || name == playlist.name) return;
  await ref.read(playlistsRepositoryProvider).rename(playlist.id, name);
}

Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Playlist playlist) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.playlistDeleteConfirmTitle),
      content: Text(l10n.playlistDeleteConfirmBody(playlist.name)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.commonDelete)),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(playlistsRepositoryProvider).delete(playlist.id);
}
