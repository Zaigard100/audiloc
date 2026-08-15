import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import '../../services/playback/player_service.dart';
import '../library/providers/library_providers.dart';
import 'models/queue_source.dart';
import 'providers/player_providers.dart';

/// Full-screen player (ТЗ п.6.1): reached by swiping up / tapping the mini
/// player. Large cover, seek bar, transport controls, favorite toggle.
class FullPlayerScreen extends ConsumerWidget {
  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final position = ref.watch(playbackPositionProvider).value;
    final isFavorite = track == null
        ? false
        : ref.watch(favoriteIdsProvider).value?.contains(track.id) ?? false;
    final queueSource = ref.watch(queueSourceProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.playerNowPlayingTitle),
      ),
      body: track == null
          ? Center(child: Text(l10n.playerNothingPlaying))
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Cap the cover by both width and height so short
                  // viewports (small windows, landscape phones) scroll
                  // instead of overflowing — an AspectRatio(1) sized only
                  // by width would force its height past whatever room is
                  // actually left.
                  final coverSize = (constraints.maxHeight * 0.4).clamp(120.0, constraints.maxWidth - 48);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: coverSize,
                            height: coverSize,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: track.coverPath != null
                                  ? Image.file(File(track.coverPath!), fit: BoxFit.cover)
                                  : const ColoredBox(
                                      color: AppTheme.surfaceHigh,
                                      child: Icon(Icons.music_note, size: 64, color: AppTheme.onSurfaceMuted),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            track.displayTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.displayArtist,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 15),
                          ),
                          if (_sourceLabel(l10n, queueSource) case final label?) ...[
                            const SizedBox(height: 8),
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _SeekBar(position: position, onSeek: (d) => ref.read(playerServiceProvider).seek(d)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                                color: isFavorite ? AppTheme.accent : AppTheme.onSurfaceMuted,
                                iconSize: 28,
                                onPressed: () => ref.read(favoritesRepositoryProvider).toggle(track.id),
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_previous),
                                iconSize: 40,
                                onPressed: () => ref.read(playerServiceProvider).previous(),
                              ),
                              IconButton(
                                icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                                iconSize: 64,
                                color: AppTheme.accent,
                                onPressed: () => ref.read(playerServiceProvider).playOrPause(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next),
                                iconSize: 40,
                                onPressed: () => ref.read(playerServiceProvider).next(),
                              ),
                              const SizedBox(width: 28),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String? _sourceLabel(AppLocalizations l10n, QueueSource? source) => switch (source) {
        null => null,
        LibraryQueueSource() => l10n.playerSourceLibrary,
        FavoritesQueueSource() => l10n.playerSourceFavorites,
        PlaylistQueueSource(:final name) => l10n.playerSourcePlaylist(name),
      };
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.position, required this.onSeek});

  final PlaybackPositionState? position;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final current = position?.position ?? Duration.zero;
    final total = position?.duration ?? Duration.zero;
    return Column(
      children: [
        Slider(
          value: total.inMilliseconds == 0
              ? 0
              : current.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
          max: total.inMilliseconds == 0 ? 1 : total.inMilliseconds.toDouble(),
          onChanged: total.inMilliseconds == 0
              ? null
              : (value) => onSeek(Duration(milliseconds: value.round())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_format(current), style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12)),
              Text(_format(total), style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
