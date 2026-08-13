import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/playlist.dart';
import '../../../data/models/playlist_track.dart';
import '../../../data/models/track.dart';

final playlistsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(playlistsRepositoryProvider).watchPlaylists(),
);

final playlistTracksProvider = StreamProvider.family<List<Track>, String>(
  (ref, playlistId) => ref.watch(playlistsRepositoryProvider).watchTracks(playlistId),
);

/// Tracks with their `playlist_tracks.id`, for removal-by-entry in the UI.
final playlistItemsProvider = StreamProvider.family<List<PlaylistItem>, String>(
  (ref, playlistId) => ref.watch(playlistsRepositoryProvider).watchItems(playlistId),
);
