/// Where the currently-playing queue came from — set alongside every
/// `PlayerService.setQueue(...)` call, purely for display in
/// [FullPlayerScreen] ("Играет: Библиотека" / "Играет: Избранное" /
/// "Играет: Плейлист «Name»"). Not part of `PlayerService` itself: this
/// is a UI-layer label, not something the player engine needs to know.
sealed class QueueSource {
  const QueueSource();
}

class LibraryQueueSource extends QueueSource {
  const LibraryQueueSource();
}

class FavoritesQueueSource extends QueueSource {
  const FavoritesQueueSource();
}

class PlaylistQueueSource extends QueueSource {
  const PlaylistQueueSource(this.playlistId, this.name);

  /// Needed to rebuild the queue when restoring/resuming a synced
  /// playback position (docs/adr/0029-playback-state-sync.md) — [name]
  /// alone is display-only and can't be looked up back into a specific
  /// playlist (two playlists can share a name).
  final String playlistId;
  final String name;
}
