import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';

/// Long-press action shared by every library track list: confirm, then
/// soft-delete (ТЗ: "в БД он будет просто забанен, но на устройстве
/// нет" — `TracksRepository.delete` only flags the row, the file on disk
/// is never touched, and it's restorable from the "Удалённые" tab).
Future<void> confirmAndDeleteTrack(BuildContext context, WidgetRef ref, Track track) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Удалить трек из библиотеки?'),
      content: Text(
        '«${track.displayTitle}» пропадёт из библиотеки на этом устройстве. '
        'Сам файл не удаляется — трек можно вернуть на вкладке «Удалённые».',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Удалить')),
      ],
    ),
  );
  if (confirmed != true) return;

  await ref.read(tracksRepositoryProvider).delete(track.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('«${track.displayTitle}» удалён из библиотеки')),
    );
  }
}
