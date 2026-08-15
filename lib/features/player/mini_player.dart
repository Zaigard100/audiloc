import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../library/providers/library_providers.dart';
import 'full_player_screen.dart';
import 'providers/player_providers.dart';

/// Bottom mini-player (ТЗ п.6.1): cover, progress, favorite, play/pause.
/// Tap or swipe up to expand into [FullPlayerScreen].
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    if (track == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final position = ref.watch(playbackPositionProvider).value;
    final isFavorite = ref.watch(favoriteIdsProvider).value?.contains(track.id) ?? false;

    void openFullPlayer() {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FullPlayerScreen()));
    }

    return GestureDetector(
      onTap: openFullPlayer,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -200) openFullPlayer();
      },
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: position == null || position.duration == Duration.zero
                  ? 0
                  : position.fraction.clamp(0, 1),
              minHeight: 2,
              backgroundColor: context.colors.divider,
              valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _MiniCover(coverPath: track.coverPath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                    color: isFavorite ? AppTheme.accent : context.colors.onSurfaceMuted,
                    onPressed: () => ref.read(favoritesRepositoryProvider).toggle(track.id),
                  ),
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    iconSize: 36,
                    color: context.colors.onSurface,
                    onPressed: () => ref.read(playerServiceProvider).playOrPause(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.coverPath});

  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 44,
        child: coverPath != null
            ? Image.file(File(coverPath!), fit: BoxFit.cover)
            : ColoredBox(
                color: context.colors.surfaceHigh,
                child: Icon(Icons.music_note, color: context.colors.onSurfaceMuted),
              ),
      ),
    );
  }
}
