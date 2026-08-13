import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../providers/library_providers.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.trailing,
    this.onLongPress,
  });

  final Track track;
  final VoidCallback onTap;
  final Widget? trailing;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(favoriteIdsProvider).value?.contains(track.id) ?? false;
    final transfers = ref.watch(activeTransfersProvider).value ?? const {};
    final isTransferring = transfers.containsKey(track.id);
    final fraction = transfers[track.id];

    final tile = ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: track.coverPath != null
              ? Image.file(File(track.coverPath!), fit: BoxFit.cover)
              : const ColoredBox(
                  color: AppTheme.surfaceHigh,
                  child: Icon(Icons.music_note, color: AppTheme.onSurfaceMuted),
                ),
        ),
      ),
      title: Row(
        children: [
          if (!track.isAvailableLocally) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: isTransferring
                  ? CircularProgressIndicator(strokeWidth: 2, value: fraction, color: AppTheme.accent)
                  : const Icon(Icons.cloud_download_outlined, size: 14, color: AppTheme.onSurfaceMuted),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(track.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      subtitle: Text(
        track.isAvailableLocally
            ? '${track.displayArtist} · ${track.displayAlbum}'
            : '${track.displayArtist} · ${track.displayAlbum} · '
                '${isTransferring ? 'загрузка${fraction == null ? '…' : ' ${(fraction * 100).round()}%'}' : 'ждёт передачи с другого устройства'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ??
          IconButton(
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
            color: isFavorite ? AppTheme.accent : AppTheme.onSurfaceMuted,
            onPressed: () => ref.read(favoritesRepositoryProvider).toggle(track.id),
          ),
    );

    // Right-click opens the same action menu as a long-press — desktop
    // has no long-press gesture, so this is the only way to reach it
    // there (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md).
    if (onLongPress == null) return tile;
    return GestureDetector(onSecondaryTap: onLongPress, child: tile);
  }
}
