import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/track_tile.dart';
import '../player/models/queue_source.dart';
import '../player/providers/player_providers.dart';

/// Поиск tab (ТЗ п.6.2): filters the already-loaded local library in
/// memory — the library is small enough (personal music collections, not
/// millions of rows) that a dedicated search index would be premature.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(filteredLibraryTracksProvider);
    final query = ref.watch(librarySearchQueryProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            hintStyle: const TextStyle(color: AppTheme.onSurfaceMuted),
            border: InputBorder.none,
          ),
          onChanged: (value) => ref.read(librarySearchQueryProvider.notifier).state = value,
        ),
      ),
      body: query.isEmpty
          ? Center(
              child: Text(l10n.searchStartTyping, style: const TextStyle(color: AppTheme.onSurfaceMuted)),
            )
          : results.isEmpty
              ? Center(child: Text(l10n.searchNothingFound, style: const TextStyle(color: AppTheme.onSurfaceMuted)))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final track = results[index];
                    return TrackTile(
                      track: track,
                      onTap: () {
                        ref.read(queueSourceProvider.notifier).state = const LibraryQueueSource();
                        ref.read(playerServiceProvider).setQueue(results, startIndex: index);
                      },
                    );
                  },
                ),
    );
  }
}
