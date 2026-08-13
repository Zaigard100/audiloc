import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';
import '../../../services/sync/files/file_sync_service.dart';

final libraryTracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(tracksRepositoryProvider).watchAll(),
);

final favoriteIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(favoritesRepositoryProvider).watchFavoriteIds(),
);

final librarySearchQueryProvider = StateProvider<String>((ref) => '');

final filteredLibraryTracksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(libraryTracksProvider).value ?? const [];
  final query = ref.watch(librarySearchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return tracks;
  return tracks
      .where((t) =>
          t.displayTitle.toLowerCase().contains(query) ||
          t.displayArtist.toLowerCase().contains(query) ||
          t.displayAlbum.toLowerCase().contains(query))
      .toList();
});

/// What field the Library tab's flat track list is currently sorted by.
enum LibrarySortField { title, artist, addedAt }

class LibrarySortState {
  const LibrarySortState({this.field = LibrarySortField.title, this.descending = false});

  final LibrarySortField field;
  final bool descending;
}

final librarySortProvider = StateProvider<LibrarySortState>((ref) => const LibrarySortState());

/// The Library tab's "Все" list: `libraryTracksProvider`, sorted in memory
/// per [librarySortProvider]. A plain `List.sort` rather than a SQL
/// `ORDER BY` — a personal music collection is at most a few thousand
/// rows, cheap to sort client-side, and this avoids a family of near-
/// identical repository queries for what's a pure display concern.
final sortedLibraryTracksProvider = Provider<List<Track>>((ref) {
  final tracks = <Track>[...ref.watch(libraryTracksProvider).value ?? const []];
  final sort = ref.watch(librarySortProvider);

  int compare(Track a, Track b) => switch (sort.field) {
        LibrarySortField.title => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
        LibrarySortField.artist => a.displayArtist.toLowerCase().compareTo(b.displayArtist.toLowerCase()),
        LibrarySortField.addedAt =>
          (a.modifiedAt ?? DateTime(0)).compareTo(b.modifiedAt ?? DateTime(0)),
      };
  tracks.sort(sort.descending ? (a, b) => compare(b, a) : compare);
  return tracks;
});

/// "Избранное" as a live view, not a maintained playlist (ТЗ п.6.5): a
/// track appears here for exactly as long as its heart is toggled on,
/// with no separate storage or upkeep beyond `favorites`. Sorted by
/// [favoritedAtProvider], most recently favorited first.
final favoriteTracksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(libraryTracksProvider).value ?? const [];
  final favoritedAt = ref.watch(favoritedAtProvider).value ?? const {};
  final favorites = tracks.where((t) => favoritedAt.containsKey(t.id)).toList()
    ..sort((a, b) => favoritedAt[b.id]!.compareTo(favoritedAt[a.id]!));
  return favorites;
});

/// When each currently-favorited track was (last) favorited — powers the
/// "newest first" order of [favoriteTracksProvider]. Separate from
/// [favoriteIdsProvider] (a plain `Set<String>`, used everywhere for the
/// heart-icon toggle state) since most call sites only need membership,
/// not a timestamp.
final favoritedAtProvider = StreamProvider<Map<String, DateTime>>(
  (ref) => ref.watch(favoritesRepositoryProvider).watchFavoritedAt(),
);

/// Soft-deleted tracks ("Удалённые"): hidden from the library, file left
/// alone on disk, restorable — see `TracksRepository.delete`/`.restore`.
final deletedTracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(tracksRepositoryProvider).watchDeleted(),
);

/// Tracks known via synced metadata but not yet downloaded to this
/// device — `services/sync/files` fetches these automatically once a
/// peer with the file is online.
final missingFilesProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(tracksRepositoryProvider).watchMissingFiles(),
);

/// Live download progress for tracks currently being fetched from a peer:
/// `trackId -> fraction` (`null` fraction means "in progress, size
/// unknown" rather than "not downloading"). Entries disappear as soon as
/// their download stops, successfully or not — see [TransferFinished].
final activeTransfersProvider = StreamProvider<Map<String, double?>>((ref) async* {
  final service = await ref.watch(fileSyncServiceProvider.future);
  var current = <String, double?>{};
  yield current;
  await for (final event in service.transferEvents) {
    current = Map.of(current);
    switch (event) {
      case TransferProgress(:final trackId, :final fraction):
        current[trackId] = fraction;
      case TransferFinished(:final trackId):
        current.remove(trackId);
    }
    yield current;
  }
});
