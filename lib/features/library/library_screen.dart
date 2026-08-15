import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../services/library_import/library_import_service.dart';
import '../player/models/queue_source.dart';
import '../player/providers/player_providers.dart';
import 'providers/library_providers.dart';
import 'widgets/track_actions_sheet.dart';
import 'widgets/track_tile.dart';

/// Библиотека tab (ТЗ п.6.2): a flat, sortable list of every track. Long-
/// press (or right-click on desktop) opens an action menu — edit, add to
/// playlist, "Поделиться", delete (see [showTrackActionsSheet]). Delete
/// is a soft-delete — the file itself is never touched, and it stays
/// recoverable from "Удалённые" on the Плейлисты tab (docs/adr/0014).
/// "Избранное" and "Жанры" used to be tabs here too; Избранное moved to
/// Плейлисты as a live view of its own, and "Жанры" was removed outright,
/// not just relocated (`Track.genre` itself is still editable, though —
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navLibrary),
        actions: [
          _SortMenuButton(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.libraryAddTrackTooltip,
            onPressed: () => _importFiles(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: l10n.libraryAddFolderTooltip,
            onPressed: () => _importFolder(context, ref),
          ),
        ],
      ),
      body: tracksAsync.when(
        data: (allTracks) => allTracks.isEmpty
            ? _EmptyLibrary(onImport: () => _importFolder(context, ref))
            : const _SortedTrackList(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.libraryLoadError(error))),
      ),
    );
  }

  static Future<void> _importFolder(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.libraryPickFolderDialogTitle,
    );
    if (path == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(l10n.libraryImportStarted)));

    final importService = await ref.read(libraryImportServiceProvider.future);
    final result = await importService.importDirectory(Directory(path));

    messenger.showSnackBar(SnackBar(
      content: Text(l10n.libraryImportResult(result.imported, result.skippedDuplicates, result.failed)),
    ));
  }

  static Future<void> _importFiles(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.libraryPickFilesDialogTitle,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        for (final ext in LibraryImportService.supportedExtensions) ext.substring(1),
      ],
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(l10n.libraryImportStarted)));

    final importService = await ref.read(libraryImportServiceProvider.future);
    final files = [for (final f in result.files) if (f.path != null) File(f.path!)];
    final imported = await importService.importFiles(files);

    messenger.showSnackBar(SnackBar(
      content: Text(l10n.libraryImportResult(imported.imported, imported.skippedDuplicates, imported.failed)),
    ));
  }
}

class _SortMenuButton extends ConsumerWidget {
  const _SortMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(librarySortProvider);
    final l10n = context.l10n;
    final labels = {
      LibrarySortField.title: l10n.librarySortTitle,
      LibrarySortField.artist: l10n.librarySortArtist,
      LibrarySortField.addedAt: l10n.librarySortAddedAt,
    };
    return PopupMenuButton<LibrarySortField>(
      icon: const Icon(Icons.sort),
      tooltip: l10n.librarySortTooltip,
      onSelected: (field) {
        ref.read(librarySortProvider.notifier).state = LibrarySortState(
          field: field,
          descending: sort.field == field ? !sort.descending : false,
        );
      },
      itemBuilder: (context) => [
        for (final entry in labels.entries)
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
          onLongPress: () => showTrackActionsSheet(context, ref, track),
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
            Icon(Icons.library_music_outlined, size: 64, color: context.colors.onSurfaceMuted),
            const SizedBox(height: 16),
            Text(context.l10n.libraryEmptyTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              context.l10n.libraryEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.onSurfaceMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(context.l10n.libraryPickFolderButton),
            ),
          ],
        ),
      ),
    );
  }
}
