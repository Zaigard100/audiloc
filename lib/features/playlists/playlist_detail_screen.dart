import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/playlist.dart';
import '../../data/models/playlist_track.dart';
import '../../l10n/l10n.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/track_tile.dart';
import '../player/models/queue_source.dart';
import '../player/providers/player_providers.dart';
import 'providers/playlists_providers.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId, this.playlist});

  final String playlistId;
  final Playlist? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(playlistItemsProvider(playlistId));
    final l10n = context.l10n;
    final name = playlist?.name ??
        (ref.watch(playlistsProvider).value ?? const [])
            .cast<Playlist?>()
            .firstWhere((p) => p?.id == playlistId, orElse: () => null)
            ?.name ??
        l10n.playlistFallbackName;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTrackSheet(context, ref),
        child: const Icon(Icons.playlist_add),
      ),
      body: itemsAsync.when(
        data: (items) => items.isEmpty
            ? Center(
                child: Text(l10n.playlistEmptyTracks, style: TextStyle(color: context.colors.onSurfaceMuted)),
              )
            : ReorderableListView.builder(
                itemCount: items.length,
                onReorderItem: (oldIndex, newIndex) => _reorder(ref, items, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return TrackTile(
                    key: ValueKey(item.entryId),
                    track: item.track,
                    onTap: () {
                      ref.read(queueSourceProvider.notifier).state = PlaylistQueueSource(playlistId, name);
                      ref
                          .read(playerServiceProvider)
                          .setQueue(items.map((e) => e.track).toList(), startIndex: index);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      color: context.colors.onSurfaceMuted,
                      onPressed: () => ref.read(playlistsRepositoryProvider).removeEntry(item.entryId),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonErrorPrefix(error))),
      ),
    );
  }

  /// [newIndex] (via `onReorderItem`) already accounts for [oldIndex]'s
  /// item being removed — it's the item's final index in the post-move
  /// list. `moveEntry`'s `beforePosition`/`afterPosition` mean exactly
  /// "the neighbour that should end up smaller/larger", so the
  /// neighbours of that post-move list are exactly what it needs.
  Future<void> _reorder(WidgetRef ref, List<PlaylistItem> items, int oldIndex, int newIndex) async {
    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final before = newIndex > 0 ? reordered[newIndex - 1].position : null;
    final after = newIndex < reordered.length - 1 ? reordered[newIndex + 1].position : null;
    await ref
        .read(playlistsRepositoryProvider)
        .moveEntry(moved.entryId, beforePosition: before, afterPosition: after);
  }

  Future<void> _showAddTrackSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddTracksSheet(playlistId: playlistId),
    );
  }
}

/// Multi-select + search for adding tracks to a playlist. Replaces the
/// old "tap a track, it's added, the sheet closes" flow — picking more
/// than one track used to mean reopening the sheet from scratch for
/// every single one.
class _AddTracksSheet extends ConsumerStatefulWidget {
  const _AddTracksSheet({required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<_AddTracksSheet> createState() => _AddTracksSheetState();
}

class _AddTracksSheetState extends ConsumerState<_AddTracksSheet> {
  final _searchController = TextEditingController();
  final _selectedIds = <String>{};
  var _query = '';
  var _adding = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTracks = ref.watch(libraryTracksProvider).value ?? const [];
    final currentIds =
        (ref.watch(playlistItemsProvider(widget.playlistId)).value ?? const []).map((e) => e.track.id).toSet();
    final query = _query.trim().toLowerCase();
    final available = allTracks.where((t) => !currentIds.contains(t.id)).where((t) {
      if (query.isEmpty) return true;
      return t.displayTitle.toLowerCase().contains(query) || t.displayArtist.toLowerCase().contains(query);
    }).toList();
    final l10n = context.l10n;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.playlistSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: available.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty ? l10n.playlistAllTracksAdded : l10n.playlistNothingFound,
                        style: TextStyle(color: context.colors.onSurfaceMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: available.length,
                      itemBuilder: (context, index) {
                        final track = available[index];
                        final selected = _selectedIds.contains(track.id);
                        return TrackTile(
                          track: track,
                          trailing: Checkbox(value: selected, onChanged: (_) => _toggle(track.id)),
                          onTap: () => _toggle(track.id),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _selectedIds.isEmpty || _adding ? null : _addSelected,
                child: _adding
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_selectedIds.isEmpty
                        ? l10n.playlistAddButton
                        : l10n.playlistAddButtonWithCount(_selectedIds.length)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String trackId) => setState(() {
        if (!_selectedIds.remove(trackId)) _selectedIds.add(trackId);
      });

  Future<void> _addSelected() async {
    setState(() => _adding = true);
    final repository = ref.read(playlistsRepositoryProvider);
    for (final trackId in _selectedIds) {
      await repository.addTrack(widget.playlistId, trackId);
    }
    if (mounted) Navigator.of(context).pop();
  }
}
