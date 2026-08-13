import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';

/// Edits a track's own metadata (title/artist/album/genre) and, on the
/// user's own request, its cover art — by default a track already has a
/// cover pulled from its tags, this just lets it be overridden with a
/// picked image. Requires the file to actually be here
/// ([Track.isAvailableLocally]): `TracksRepository.upsert` needs a local
/// path, and there's nothing else to edit metadata *for* until the file
/// (or at least its tags) exist on this device.
Future<void> showEditTrackDialog(BuildContext context, WidgetRef ref, Track track) async {
  final titleController = TextEditingController(text: track.title);
  final artistController = TextEditingController(text: track.artist);
  final albumController = TextEditingController(text: track.album);
  final genreController = TextEditingController(text: track.genre);
  var coverPath = track.coverPath;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Редактировать трек'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final result = await FilePicker.pickFiles(
                      dialogTitle: 'Выберите обложку',
                      type: FileType.image,
                    );
                    final pickedPath = result?.files.single.path;
                    if (pickedPath == null) return;
                    final cacheDir = await ref.read(coverCacheDirProvider.future);
                    // A unique filename per pick, not the track's usual
                    // `<id>.cover` — reusing that exact path would leave
                    // both this preview and every other widget showing
                    // this track's cover (TrackTile, mini player, ...)
                    // stuck on Flutter's `FileImage` cache, which keys
                    // purely on the path string and has no idea the bytes
                    // underneath just changed. A fresh path is a
                    // guaranteed cache miss everywhere, immediately.
                    final dest = File(
                      p.join(cacheDir.path, '${track.id}-${DateTime.now().millisecondsSinceEpoch}.cover'),
                    );
                    await File(pickedPath).copy(dest.path);
                    setState(() => coverPath = dest.path);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: coverPath != null
                          ? Image.file(File(coverPath!), fit: BoxFit.cover)
                          : const ColoredBox(
                              color: AppTheme.surfaceHigh,
                              child: Icon(Icons.add_photo_alternate_outlined, color: AppTheme.onSurfaceMuted),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 8),
              TextField(controller: artistController, decoration: const InputDecoration(labelText: 'Исполнитель')),
              const SizedBox(height: 8),
              TextField(controller: albumController, decoration: const InputDecoration(labelText: 'Альбом')),
              const SizedBox(height: 8),
              TextField(controller: genreController, decoration: const InputDecoration(labelText: 'Жанр')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Сохранить')),
        ],
      ),
    ),
  );
  if (saved != true) return;

  await ref.read(tracksRepositoryProvider).upsert(track.copyWith(
        title: titleController.text.trim(),
        artist: artistController.text.trim(),
        album: albumController.text.trim(),
        genre: genreController.text.trim(),
        coverPath: coverPath,
      ));
}
