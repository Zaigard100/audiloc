import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';
import '../../../l10n/l10n.dart';

/// Long-press action shared by every library track list: confirm, then
/// soft-delete (ТЗ: "в БД он будет просто забанен, но на устройстве
/// нет" — `TracksRepository.delete` only flags the row, the file on disk
/// is never touched, and it's restorable from the "Удалённые" tab).
Future<void> confirmAndDeleteTrack(BuildContext context, WidgetRef ref, Track track) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.trackDeleteConfirmTitle),
      content: Text(l10n.trackDeleteConfirmBody(track.displayTitle)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.commonDelete)),
      ],
    ),
  );
  if (confirmed != true) return;

  await ref.read(tracksRepositoryProvider).delete(track.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.trackDeletedSnackbar(track.displayTitle))),
    );
  }
}
