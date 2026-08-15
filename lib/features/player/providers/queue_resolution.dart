import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/playback_state.dart';
import '../../../data/models/playlist.dart';
import '../../../data/models/track.dart';
import '../../library/providers/library_providers.dart';
import '../../playlists/providers/playlists_providers.dart';
import '../models/queue_source.dart';

/// Waits for [provider]'s first emission — **not** just `ref.read(provider.future)`
/// on its own, which isn't enough: Riverpod 3 pauses a `StreamProvider`'s
/// underlying `StreamSubscription` while nothing is actively listening to
/// it (see `riverpod`'s CHANGELOG — "StreamProvider now pauses its
/// StreamSubscription when the provider is not actively listened"). Callers
/// of this typically run from places with no guarantee anything else is
/// watching the same provider at that exact moment (e.g.
/// `AppShell.initState`) — a bare `.future` read would then await a paused
/// stream that never emits. `listenManual` with a no-op callback is what
/// actually keeps the subscription unpaused for the moment it takes to get
/// a first value; closed again immediately after, so this doesn't keep the
/// provider alive past what it would be anyway.
Future<T> awaitFirstValue<T>(WidgetRef ref, StreamProvider<T> provider) {
  final sub = ref.listenManual(provider, (_, __) {});
  return ref.read(provider.future).whenComplete(sub.close);
}

/// Resolves [source] into its full, currently-ordered track list — the
/// same lists [FullPlayerScreen]/library/favorites/playlist screens show,
/// not a snapshot frozen at some earlier point. `null` (no active queue)
/// resolves the same as [LibraryQueueSource] — "nothing more specific has
/// been chosen" defaults to the whole library, matching
/// `queueSourceProvider`'s own initial state.
///
/// Used both to resolve a synced/restored [state] (docs/adr/0029) and to
/// build the queue pushed to a remote-controlled device
/// (docs/adr/0030-remote-playback-control.md) — both need "what would
/// this device's own queue look like right now", not just a single track.
Future<List<Track>> resolveQueueTracks(WidgetRef ref, QueueSource? source) async {
  switch (source) {
    case PlaylistQueueSource(:final playlistId):
      final items = await awaitFirstValue(ref, playlistItemsProvider(playlistId));
      return items.map((e) => e.track).toList();
    case FavoritesQueueSource():
      await awaitFirstValue(ref, libraryTracksProvider);
      await awaitFirstValue(ref, favoritedAtProvider);
      return ref.read(favoriteTracksProvider);
    case LibraryQueueSource():
    case null:
      await awaitFirstValue(ref, libraryTracksProvider);
      return ref.read(sortedLibraryTracksProvider);
  }
}

/// Rebuilds the ordered queue a saved/synced [PlaybackState] (or the
/// equivalent fields from `LocalPlaybackStateStore`'s local session
/// bookmark) was playing from, and finds its track in it — `null` if the
/// queue or the track itself isn't resolvable on this device yet
/// (playlist not synced, track not synced, or synced but its file hasn't
/// been downloaded here). Shared by `resume_playback_prompt.dart`
/// (cross-device sync) and `local_session_restore.dart` (this device's
/// own last session) — both need exactly this, just from different
/// sources of the three fields. See docs/adr/0029-playback-state-sync.md.
Future<(List<Track>, int, QueueSource)?> resolvePlaybackStateQueue(
  WidgetRef ref, {
  required PlaybackQueueType queueType,
  required String? playlistId,
  required String trackId,
}) async {
  final QueueSource source;
  switch (queueType) {
    case PlaybackQueueType.library:
      source = const LibraryQueueSource();
    case PlaybackQueueType.favorites:
      source = const FavoritesQueueSource();
    case PlaybackQueueType.playlist:
      if (playlistId == null) return null;
      final playlists = await awaitFirstValue(ref, playlistsProvider);
      final playlist =
          playlists.cast<Playlist?>().firstWhere((p) => p?.id == playlistId, orElse: () => null);
      if (playlist == null) return null;
      source = PlaylistQueueSource(playlistId, playlist.name);
  }

  final tracks = await resolveQueueTracks(ref, source);
  final index = tracks.indexWhere((t) => t.id == trackId && t.isAvailableLocally);
  if (index < 0) return null;
  return (tracks, index, source);
}
