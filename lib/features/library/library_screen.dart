import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import 'providers/library_providers.dart';
import 'widgets/track_tile.dart';

/// Библиотека tab (ТЗ п.6.2): плоский список треков, "Избранное" (живое
/// представление над `favorites`, не отдельно поддерживаемый плейлист —
/// трек попадает туда, пока горит сердечко, и только на это время) и
/// жанры (тоже не хранятся отдельно — просто различные `tracks.genre`).
/// Альбомы/исполнители как отдельные вкладки — см. docs/roadmap.md.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Библиотека'),
          actions: [
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'Импортировать папку',
              onPressed: () => _importFolder(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Все'),
              Tab(text: 'Избранное'),
              Tab(text: 'Жанры'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AllTracksTab(onImport: () => _importFolder(context, ref)),
            const _FavoritesTab(),
            const _GenresTab(),
          ],
        ),
      ),
    );
  }

  static Future<void> _importFolder(BuildContext context, WidgetRef ref) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Выберите папку с музыкой',
    );
    if (path == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Импорт запущен…')));

    final importService = await ref.read(libraryImportServiceProvider.future);
    final result = await importService.importDirectory(Directory(path));

    messenger.showSnackBar(SnackBar(
      content: Text(
        'Добавлено: ${result.imported}, пропущено дублей: ${result.skippedDuplicates}, ошибок: ${result.failed}',
      ),
    ));
  }
}

class _AllTracksTab extends ConsumerWidget {
  const _AllTracksTab({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    return tracksAsync.when(
      data: (tracks) => tracks.isEmpty
          ? _EmptyLibrary(onImport: onImport)
          : _TrackList(tracks: tracks),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Ошибка загрузки библиотеки: $error')),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(favoriteTracksProvider);
    if (tracks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border, size: 64, color: AppTheme.onSurfaceMuted),
              SizedBox(height: 16),
              Text(
                'Пока нет избранных треков',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Нажмите на сердечко у трека — он появится здесь',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.onSurfaceMuted),
              ),
            ],
          ),
        ),
      );
    }
    return _TrackList(tracks: tracks);
  }
}

class _GenresTab extends ConsumerWidget {
  const _GenresTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider);
    if (genres.isEmpty) {
      return const Center(
        child: Text('Жанры появятся, когда в тегах треков будет указан жанр',
            textAlign: TextAlign.center, style: TextStyle(color: AppTheme.onSurfaceMuted)),
      );
    }
    return ListView.builder(
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final genre = genres[index];
        final count = ref.watch(tracksByGenreProvider(genre)).length;
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: AppTheme.surfaceHigh,
            child: Icon(Icons.piano, color: AppTheme.onSurfaceMuted),
          ),
          title: Text(genre),
          subtitle: Text('$count треков'),
          onTap: () => context.push('/library/genre', extra: genre),
        );
      },
    );
  }
}

class _TrackList extends ConsumerWidget {
  const _TrackList({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return TrackTile(
          track: track,
          onTap: () => ref.read(playerServiceProvider).setQueue(tracks, startIndex: index),
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 64, color: AppTheme.onSurfaceMuted),
            const SizedBox(height: 16),
            const Text('Библиотека пуста', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Импортируйте папку с музыкой — теги и обложки подтянутся автоматически',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.onSurfaceMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Выбрать папку'),
            ),
          ],
        ),
      ),
    );
  }
}
