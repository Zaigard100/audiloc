import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/playback_state.dart';
import '../../../data/models/playlist.dart';
import '../../../data/models/track.dart';
import '../../../l10n/l10n.dart';
import '../../library/providers/library_providers.dart';
import '../../playlists/providers/playlists_providers.dart';
import '../models/queue_source.dart';
import '../providers/player_providers.dart';

/// Reacts to [playbackStateProvider] — see
/// docs/adr/0029-playback-state-sync.md. Two cases:
/// - Nothing loaded locally yet (a cold start, or the player's just been
///   idle since) — silently restore, paused, ready to resume with a tap.
/// - Something's already loaded here (playing or paused) — a synced
///   update from elsewhere doesn't get to yank control away
///   unannounced; ask first.
///
/// Only skips [state] as "our own write, ignore it" when something's
/// *already* loaded locally — at cold start (nothing loaded yet)
/// restoring is exactly the point even when this same device wrote the
/// row last (that's the actual "state isn't kept across a restart"
/// complaint this exists to fix); mid-session, reacting to this
/// device's own pause a moment ago (already reflected in the UI) would
/// just be a pointless self-echo.
Future<void> handleIncomingPlaybackState(BuildContext context, WidgetRef ref, PlaybackState state) async {
  final hasLocalTrack = ref.read(currentTrackProvider).value != null;
  final self = ref.read(selfDeviceProvider);
  if (hasLocalTrack && state.deviceId == self.id) return;

  // The "sync order" tracks -> playlists -> playback state the ТЗ asked
  // for isn't a transport-level thing `crdt_sync` actually exposes (one
  // merge call already writes every table in a changeset together, see
  // the ADR) — what actually matters, and what this *is*, is a
  // resolvability gate: a playback_state row is only actionable once
  // its referenced track (and playlist, if any) already exist locally.
  // If they don't (yet), silently do nothing rather than resume into a
  // half-known state — nothing about this row changes again on its own,
  // but in practice the reference and its target always arrive in the
  // same merge, so this is a safety net, not the primary mechanism.
  final resolved = await _resolveQueue(ref, state);
  if (resolved == null) return;
  final (tracks, startIndex, source) = resolved;

  if (hasLocalTrack) {
    if (!context.mounted) return;
    final l10n = context.l10n;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.resumePlaybackTitle),
        content: Text(l10n.resumePlaybackBody(
          tracks[startIndex].displayTitle,
          _formatPosition(state.position),
          state.deviceName,
        )),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonNo)),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.resumePlaybackContinue),
          ),
        ],
      ),
    );
    if (proceed != true) return;
  }

  final playerService = ref.read(playerServiceProvider);
  await playerService.setQueue(tracks, startIndex: startIndex, autoPlay: false);
  await playerService.seek(state.position);
  ref.read(queueSourceProvider.notifier).state = source;
}

/// Rebuilds the ordered track list [state] was playing from, and finds
/// [PlaybackState.trackId] in it — `null` if the queue or the track
/// itself isn't resolvable on this device yet (playlist not synced,
/// track not synced, or synced but its file hasn't been downloaded
/// here).
Future<(List<Track>, int, QueueSource)?> _resolveQueue(WidgetRef ref, PlaybackState state) async {
  final List<Track> tracks;
  final QueueSource source;
  switch (state.queueType) {
    case PlaybackQueueType.library:
      await _awaitFirstValue(ref, libraryTracksProvider);
      tracks = ref.read(sortedLibraryTracksProvider);
      source = const LibraryQueueSource();
    case PlaybackQueueType.favorites:
      await _awaitFirstValue(ref, libraryTracksProvider);
      await _awaitFirstValue(ref, favoritedAtProvider);
      tracks = ref.read(favoriteTracksProvider);
      source = const FavoritesQueueSource();
    case PlaybackQueueType.playlist:
      final playlistId = state.playlistId;
      if (playlistId == null) return null;
      final playlists = await _awaitFirstValue(ref, playlistsProvider);
      final playlist =
          playlists.cast<Playlist?>().firstWhere((p) => p?.id == playlistId, orElse: () => null);
      if (playlist == null) return null;
      final items = await _awaitFirstValue(ref, playlistItemsProvider(playlistId));
      if (items.isEmpty) return null;
      tracks = items.map((e) => e.track).toList();
      source = PlaylistQueueSource(playlistId, playlist.name);
  }

  final index = tracks.indexWhere((t) => t.id == state.trackId && t.isAvailableLocally);
  if (index < 0) return null;
  return (tracks, index, source);
}

/// Waits for [provider]'s first emission — **not** just `ref.read(provider.future)`
/// on its own, which isn't enough: Riverpod 3 pauses a `StreamProvider`'s
/// underlying `StreamSubscription` while nothing is actively listening to
/// it (see `riverpod`'s CHANGELOG — "StreamProvider now pauses its
/// StreamSubscription when the provider is not actively listened"). This
/// function typically runs from `AppShell.initState`, with no guarantee
/// anything else is watching e.g. `libraryTracksProvider` at that exact
/// moment — a bare `.future` read would then await a paused stream that
/// never emits, and the whole restore would silently do nothing forever.
/// `listenManual` with a no-op callback is what actually keeps the
/// subscription unpaused for the moment it takes to get a first value;
/// closed again immediately after, so this doesn't keep the provider
/// alive past what it would be anyway.
Future<T> _awaitFirstValue<T>(WidgetRef ref, StreamProvider<T> provider) {
  final sub = ref.listenManual(provider, (_, __) {});
  return ref.read(provider.future).whenComplete(sub.close);
}

String _formatPosition(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
