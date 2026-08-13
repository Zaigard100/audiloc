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

    return ListTile(
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
      title: Text(track.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${track.displayArtist} · ${track.displayAlbum}',
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
  }
}
