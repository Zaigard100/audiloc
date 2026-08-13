import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'providers/library_providers.dart';
import 'widgets/track_tile.dart';

/// Библиотека tab (ТЗ п.6.2): treats — for the MVP — the flat track list
/// as the primary view; album/genre/artist groupings are a follow-up (see
/// docs/roadmap.md), the data model already supports them (`tracks.album`,
/// `.genre`, `.artist` are just columns away from a GROUP BY).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(libraryTracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Импортировать папку',
            onPressed: () => _importFolder(context, ref),
          ),
        ],
      ),
      body: tracksAsync.when(
        data: (tracks) => tracks.isEmpty
            ? _EmptyLibrary(onImport: () => _importFolder(context, ref))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return TrackTile(
                    track: track,
                    onTap: () => ref.read(playerServiceProvider).setQueue(tracks, startIndex: index),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Ошибка загрузки библиотеки: $error')),
      ),
    );
  }

  Future<void> _importFolder(BuildContext context, WidgetRef ref) async {
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
