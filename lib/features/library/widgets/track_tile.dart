import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../l10n/l10n.dart';
import '../../player/providers/player_providers.dart';
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
    final l10n = context.l10n;
    // Otherwise identical tracks in different lists (Библиотека, a
    // playlist, search results) gave no visual clue which one the mini
    // player was actually on — easy to lose track of, especially in a
    // long list.
    final isCurrent = ref.watch(currentTrackProvider).value?.id == track.id;
    final isPlaying = isCurrent && (ref.watch(isPlayingProvider).value ?? false);

    final tile = ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      tileColor: isCurrent ? AppTheme.accent.withValues(alpha: 0.08) : null,
      leading: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 48,
              height: 48,
              child: track.coverPath != null
                  ? Image.file(File(track.coverPath!), fit: BoxFit.cover)
                  : ColoredBox(
                      color: context.colors.surfaceHigh,
                      child: Icon(Icons.music_note, color: context.colors.onSurfaceMuted),
                    ),
            ),
          ),
          if (isCurrent)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                child: Icon(
                  isPlaying ? Icons.volume_up : Icons.pause,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          if (!track.isAvailableLocally) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: isTransferring
                  ? CircularProgressIndicator(strokeWidth: 2, value: fraction, color: AppTheme.accent)
                  : Icon(Icons.cloud_download_outlined, size: 14, color: context.colors.onSurfaceMuted),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              track.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isCurrent
                  ? const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)
                  : null,
            ),
          ),
        ],
      ),
      subtitle: Text(
        track.isAvailableLocally
            ? '${track.displayArtist} · ${track.displayAlbum}'
            : '${track.displayArtist} · ${track.displayAlbum} · '
                '${isTransferring ? (fraction == null ? l10n.trackDownloadingIndeterminate : l10n.trackDownloadingPercent((fraction * 100).round())) : l10n.trackWaitingForTransfer}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ??
          IconButton(
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
            color: isFavorite ? AppTheme.accent : context.colors.onSurfaceMuted,
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
