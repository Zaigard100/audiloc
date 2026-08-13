import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/track.dart';
import 'add_to_playlist_sheet.dart';
import 'delete_track_action.dart';
import 'edit_track_dialog.dart';
import 'share_track_sheet.dart';

/// Long-press (or right-click on desktop) action menu for a track —
/// replaces the old "long-press deletes immediately" behavior with a
/// proper choice of what to do.
Future<void> showTrackActionsSheet(BuildContext context, WidgetRef ref, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Редактировать'),
            enabled: track.isAvailableLocally,
            subtitle: track.isAvailableLocally ? null : const Text('Файл ещё не загружен на это устройство'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showEditTrackDialog(context, ref, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Добавить в плейлист'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showAddToPlaylistSheet(context, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Поделиться'),
            enabled: track.isAvailableLocally,
            subtitle: track.isAvailableLocally ? null : const Text('Файл ещё не загружен на это устройство'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showShareTrackSheet(context, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Удалить'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              confirmAndDeleteTrack(context, ref, track);
            },
          ),
        ],
      ),
    ),
  );
}
