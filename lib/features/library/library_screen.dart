import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/library_import/library_import_service.dart';
import '../player/models/queue_source.dart';
import '../player/providers/player_providers.dart';
import 'providers/library_providers.dart';
import 'widgets/delete_track_action.dart';
import 'widgets/track_tile.dart';

/// Библиотека tab (ТЗ п.6.2): a flat, sortable list of every track. Long-
/// press soft-deletes (see [confirmAndDeleteTrack]) — the file itself is
/// never touched, and it stays recoverable from "Удалённые" on the
/// Плейлисты tab (docs/adr/0014). "Избранное" and "Жанры" used to be
/// tabs here too; Избранное moved to Плейлисты as a live view of its
/// own, and "Жанры" was removed outright, not just relocated.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(libraryTracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        actions: [
          _SortMenuButton(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Добавить трек',
            onPressed: () => _importFiles(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Добавить папку',
            onPressed: () => _importFolder(context, ref),
          ),
        ],
      ),
      body: tracksAsync.when(
        data: (allTracks) => allTracks.isEmpty
            ? _EmptyLibrary(onImport: () => _importFolder(context, ref))
            : const _SortedTrackList(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Ошибка загрузки библиотеки: $error')),
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

  static Future<void> _importFiles(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Выберите треки',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        for (final ext in LibraryImportService.supportedExtensions) ext.substring(1),
      ],
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Импорт запущен…')));

    final importService = await ref.read(libraryImportServiceProvider.future);
    final files = [for (final f in result.files) if (f.path != null) File(f.path!)];
    final imported = await importService.importFiles(files);

    messenger.showSnackBar(SnackBar(
      content: Text(
        'Добавлено: ${imported.imported}, пропущено дублей: ${imported.skippedDuplicates}, ошибок: ${imported.failed}',
      ),
    ));
  }
}

class _SortMenuButton extends ConsumerWidget {
  const _SortMenuButton();

  static const _labels = {
    LibrarySortField.title: 'Название',
    LibrarySortField.artist: 'Исполнитель',
    LibrarySortField.addedAt: 'Дата добавления',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(librarySortProvider);
    return PopupMenuButton<LibrarySortField>(
      icon: const Icon(Icons.sort),
      tooltip: 'Сортировка',
      onSelected: (field) {
        ref.read(librarySortProvider.notifier).state = LibrarySortState(
          field: field,
          descending: sort.field == field ? !sort.descending : false,
        );
      },
      itemBuilder: (context) => [
        for (final entry in _labels.entries)
          PopupMenuItem(
            value: entry.key,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.value),
                if (sort.field == entry.key)
                  Icon(sort.descending ? Icons.arrow_downward : Icons.arrow_upward, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

class _SortedTrackList extends ConsumerWidget {
  const _SortedTrackList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(sortedLibraryTracksProvider);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return TrackTile(
          track: track,
          onTap: () {
            ref.read(queueSourceProvider.notifier).state = const LibraryQueueSource();
            ref.read(playerServiceProvider).setQueue(tracks, startIndex: index);
          },
          onLongPress: () => confirmAndDeleteTrack(context, ref, track),
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
