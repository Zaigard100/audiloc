import 'package:flutter_riverpod/flutter_riverpod.dart';

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
