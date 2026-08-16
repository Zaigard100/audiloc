import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import '../../services/playback/player_service.dart';
import '../library/providers/library_providers.dart';
import 'models/queue_source.dart';
import 'providers/active_playback_controller.dart';
import 'providers/player_providers.dart';
import 'providers/playback_ownership_providers.dart';
import 'widgets/playback_target_picker_sheet.dart';

/// Full-screen player (ТЗ п.6.1): reached by swiping up / tapping the mini
/// player, dismissed by swiping down anywhere on this screen (or the
/// back button/gesture). See [_dragStartY] for why swipe-down is tracked
/// with a raw [Listener] rather than a [GestureDetector].
class FullPlayerScreen extends ConsumerStatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> {
  /// How far the current downward drag has travelled, or `null` when no
  /// drag is in progress. A [GestureDetector]'s own `onVerticalDragEnd`
  /// would compete with the [SingleChildScrollView] below it for the
  /// gesture — and, being the descendant, the scroll view reliably wins
  /// that arena, so the swipe-down would silently never fire whenever
  /// the body happens to be scrollable (short windows, landscape
  /// phones). A raw [Listener] sits outside the gesture arena entirely:
  /// it sees every pointer event regardless of which recognizer ends up
  /// "winning", so it can close the screen without taking anything away
  /// from the scroll view's own handling of the same drag.
  double? _dragStartY;

  static const double _dismissThreshold = 120;

  /// Minimum horizontal fling speed (logical px/s) on the cover art to
  /// count as a swipe-to-skip gesture, rather than an incidental drag.
  static const double _swipeVelocityThreshold = 300;

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();
    final isRemote = target is RemotePlaybackTarget;
    final track = ref.watch(activePlaybackCurrentTrackProvider).value;
    final isPlaying = ref.watch(activePlaybackIsPlayingProvider);
    final position = ref.watch(activePlaybackPositionProvider);
    final isFavorite = track == null
        ? false
        : ref.watch(favoriteIdsProvider).value?.contains(track.id) ?? false;
    final queueSource = ref.watch(queueSourceProvider);
    // Session-only play-order toggles have no equivalent on the wire to
    // a remote device (ADR 0030 never needed one) — disabled rather
    // than silently no-op'd while this screen isn't showing this
    // device's own player.
    final shuffleEnabled = !isRemote && (ref.watch(shuffleEnabledProvider).value ?? false);
    final repeatMode = ref.watch(repeatModeProvider).value ?? PlaybackRepeatMode.all;
    final syncEnabled = ref.watch(profileSyncEnabledProvider).value ?? false;
    final controller = ref.read(activePlaybackControllerProvider);
    final l10n = context.l10n;

    return Listener(
      onPointerDown: (event) => _dragStartY = event.position.dy,
      onPointerMove: (event) {
        final startY = _dragStartY;
        if (startY == null) return;
        if (event.position.dy - startY > _dismissThreshold) {
          _dragStartY = null;
          Navigator.of(context).pop();
        }
      },
      onPointerUp: (_) => _dragStartY = null,
      onPointerCancel: (_) => _dragStartY = null,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(l10n.playerNowPlayingTitle),
          actions: [
            if (syncEnabled)
              IconButton(
                icon: Icon(isRemote ? Icons.cast_connected : Icons.cast),
                tooltip: l10n.playbackTargetPickerTitle,
                onPressed: () => showPlaybackTargetPicker(context, ref),
              ),
          ],
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
                            GestureDetector(
                              onHorizontalDragEnd: (details) {
                                final velocity = details.primaryVelocity ?? 0;
                                if (velocity <= -_swipeVelocityThreshold) {
                                  controller.next();
                                } else if (velocity >= _swipeVelocityThreshold) {
                                  controller.previous();
                                }
                              },
                              child: SizedBox(
                                width: coverSize,
                                height: coverSize,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: track.coverPath != null
                                      ? Image.file(File(track.coverPath!), fit: BoxFit.cover)
                                      : ColoredBox(
                                          color: context.colors.surfaceHigh,
                                          child:
                                              Icon(Icons.music_note, size: 64, color: context.colors.onSurfaceMuted),
                                        ),
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
                              style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 15),
                            ),
                            if (_currentSourceLabel(l10n, target, queueSource) case final label?) ...[
                              const SizedBox(height: 8),
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _SeekBar(position: position, onSeek: controller.seek),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                                  color: isFavorite ? AppTheme.accent : context.colors.onSurfaceMuted,
                                  iconSize: 28,
                                  onPressed: () => ref.read(favoritesRepositoryProvider).toggle(track.id),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_previous),
                                  iconSize: 40,
                                  onPressed: controller.previous,
                                ),
                                IconButton(
                                  icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                                  iconSize: 64,
                                  color: AppTheme.accent,
                                  onPressed: controller.playOrPause,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next),
                                  iconSize: 40,
                                  onPressed: controller.next,
                                ),
                                const SizedBox(width: 28),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.shuffle),
                                  tooltip: shuffleEnabled ? l10n.playerShuffleOn : l10n.playerShuffleOff,
                                  color: shuffleEnabled ? AppTheme.accent : context.colors.onSurfaceMuted,
                                  onPressed: isRemote
                                      ? null
                                      : () => ref.read(playerServiceProvider).setShuffle(!shuffleEnabled),
                                ),
                                const SizedBox(width: 32),
                                IconButton(
                                  icon: Icon(repeatMode == PlaybackRepeatMode.one ? Icons.repeat_one : Icons.repeat),
                                  tooltip: _repeatTooltip(l10n, repeatMode),
                                  color: repeatMode == PlaybackRepeatMode.off
                                      ? context.colors.onSurfaceMuted
                                      : AppTheme.accent,
                                  onPressed: isRemote
                                      ? null
                                      : () =>
                                          ref.read(playerServiceProvider).setRepeatMode(_nextRepeatMode(repeatMode)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  /// Remote mode replaces the usual "откуда очередь" label with which
  /// device is actually playing — the local `queueSource` describes
  /// *this* device's own last queue, not the remote one's, so showing
  /// it here while `isRemote` would be actively misleading.
  String? _currentSourceLabel(AppLocalizations l10n, ActivePlaybackTarget target, QueueSource? source) {
    if (target case RemotePlaybackTarget(:final deviceName)) {
      return l10n.playbackTargetPlayingOn(deviceName);
    }
    return switch (source) {
      null => null,
      LibraryQueueSource() => l10n.playerSourceLibrary,
      FavoritesQueueSource() => l10n.playerSourceFavorites,
      PlaylistQueueSource(:final name) => l10n.playerSourcePlaylist(name),
    };
  }

  String _repeatTooltip(AppLocalizations l10n, PlaybackRepeatMode mode) => switch (mode) {
        PlaybackRepeatMode.off => l10n.playerRepeatOff,
        PlaybackRepeatMode.all => l10n.playerRepeatAll,
        PlaybackRepeatMode.one => l10n.playerRepeatOne,
      };

  /// Off → all → one → off — same cycle order as most other players, and
  /// a direct match for `PlaybackRepeatMode`'s declaration order.
  PlaybackRepeatMode _nextRepeatMode(PlaybackRepeatMode current) => switch (current) {
        PlaybackRepeatMode.off => PlaybackRepeatMode.all,
        PlaybackRepeatMode.all => PlaybackRepeatMode.one,
        PlaybackRepeatMode.one => PlaybackRepeatMode.off,
      };
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.position, required this.onSeek});

  final PlaybackPositionState position;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final current = position.position;
    final total = position.duration;
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
              Text(_format(current), style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12)),
              Text(_format(total), style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12)),
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
