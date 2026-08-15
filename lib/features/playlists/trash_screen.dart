import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../../l10n/l10n.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/track_tile.dart';

/// "Удалённые" — soft-deleted tracks (long-press in Библиотека). Reached
/// from a card on the Плейлисты grid, not a Библиотека tab (docs/adr/0014).
/// "Восстановить" undoes the soft-delete; "Стереть навсегда" additionally
/// frees this device's local copy of the file and — since that's also
/// what `TracksRepository.watchDeleted()` looks for — makes the track
/// disappear from this screen entirely, not just lose its file. See
/// `TracksRepository.eraseFileFromDisk` for why the underlying row can
/// only ever be soft-deleted per-device, never wiped everywhere.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(deletedTracksProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trashTitle)),
      body: tracksAsync.when(
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Text(l10n.trashEmpty, style: TextStyle(color: context.colors.onSurfaceMuted)),
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
                      tooltip: l10n.trashRestoreTooltip,
                      color: AppTheme.accent,
                      onPressed: () => ref.read(tracksRepositoryProvider).restore(track.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever_outlined),
                      tooltip: l10n.trashEraseForeverTooltip,
                      color: context.colors.onSurfaceMuted,
                      onPressed: () => _confirmErase(context, ref, track),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonErrorPrefix(error))),
      ),
    );
  }

  Future<void> _confirmErase(BuildContext context, WidgetRef ref, Track track) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.trashEraseConfirmTitle),
        content: Text(l10n.trashEraseConfirmBody(track.displayTitle)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.trashEraseConfirmButton)),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(tracksRepositoryProvider).eraseFileFromDisk(track.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.trashErasedSnackbar(track.displayTitle))),
      );
    }
  }
}
