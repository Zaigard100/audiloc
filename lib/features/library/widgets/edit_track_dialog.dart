import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../l10n/l10n.dart';

/// Edits a track's own metadata (title/artist/album/genre) and, on the
/// user's own request, its cover art — by default a track already has a
/// cover pulled from its tags, this just lets it be overridden with a
/// picked image. Requires the file to actually be here
/// ([Track.isAvailableLocally]): `TracksRepository.upsert` needs a local
/// path, and there's nothing else to edit metadata *for* until the file
/// (or at least its tags) exist on this device.
Future<void> showEditTrackDialog(BuildContext context, WidgetRef ref, Track track) async {
  final l10n = context.l10n;
  final titleController = TextEditingController(text: track.title);
  final artistController = TextEditingController(text: track.artist);
  final albumController = TextEditingController(text: track.album);
  final genreController = TextEditingController(text: track.genre);
  var coverPath = track.coverPath;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(l10n.trackEditTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final result = await FilePicker.pickFiles(
                      dialogTitle: l10n.trackEditPickCoverDialogTitle,
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
                          : ColoredBox(
                              color: context.colors.surfaceHigh,
                              child: Icon(Icons.add_photo_alternate_outlined, color: context.colors.onSurfaceMuted),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(controller: titleController, decoration: InputDecoration(labelText: l10n.fieldTitle)),
              const SizedBox(height: 8),
              TextField(controller: artistController, decoration: InputDecoration(labelText: l10n.fieldArtist)),
              const SizedBox(height: 8),
              TextField(controller: albumController, decoration: InputDecoration(labelText: l10n.fieldAlbum)),
              const SizedBox(height: 8),
              TextField(controller: genreController, decoration: InputDecoration(labelText: l10n.fieldGenre)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.commonSave)),
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
