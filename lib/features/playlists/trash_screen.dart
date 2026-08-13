import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/track_tile.dart';

/// "Удалённые" — soft-deleted tracks (long-press in Библиотека). Reached
/// from a card on the Плейлисты grid, not a Библиотека tab (docs/adr/0014).
/// "Восстановить" undoes the soft-delete; "Стереть навсегда" additionally
/// frees this device's local copy of the file — see
/// `TracksRepository.eraseFileFromDisk` for why that can only ever be a
/// per-device action, never a "delete everywhere".
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(deletedTracksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Удалённые')),
      body: tracksAsync.when(
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(
              child: Text('Удалённых треков нет', style: TextStyle(color: AppTheme.onSurfaceMuted)),
            );
          }
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return TrackTile(
                track: track,
                onTap: () {}, // deleted tracks aren't queued for playback
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore),
                      tooltip: 'Вернуть в библиотеку',
                      color: AppTheme.accent,
                      onPressed: () => ref.read(tracksRepositoryProvider).restore(track.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever_outlined),
                      tooltip: 'Стереть навсегда',
                      color: AppTheme.onSurfaceMuted,
                      onPressed: () => _confirmErase(context, ref, track),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Ошибка: $error')),
      ),
    );
  }

  Future<void> _confirmErase(BuildContext context, WidgetRef ref, Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Стереть навсегда?'),
        content: Text(
          '«${track.displayTitle}» будет удалён с диска на этом устройстве. '
          'Вернуть его получится, только если файл ещё есть на каком-то '
          'другом сопряжённом устройстве — тогда он докачается заново.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Стереть')),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(tracksRepositoryProvider).eraseFileFromDisk(track.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${track.displayTitle}» стёрт с этого устройства')),
      );
    }
  }
}
