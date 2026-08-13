import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../../data/models/playlist.dart';

/// Either one of the playlist's own tracks' cover art, or a picked image
/// file — see docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md
/// and [Playlist.coverPath]'s doc for why only one of the two can apply
/// at a time.
Future<void> showPlaylistCoverPicker(BuildContext context, WidgetRef ref, Playlist playlist) async {
  final tracks = await ref.read(playlistsRepositoryProvider).watchTracks(playlist.id).first;
  final tracksWithCovers = tracks.where((t) => t.coverPath != null).toList();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Картинка из файла'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final result = await FilePicker.pickFiles(
                dialogTitle: 'Выберите обложку плейлиста',
                type: FileType.image,
              );
              final pickedPath = result?.files.single.path;
              if (pickedPath == null) return;
              final cacheDir = await ref.read(coverCacheDirProvider.future);
              final dest = File(p.join(cacheDir.path, 'playlist-${playlist.id}.cover'));
              await File(pickedPath).copy(dest.path);
              await ref.read(playlistsRepositoryProvider).setCoverFromFile(playlist.id, dest.path);
            },
          ),
          if (tracksWithCovers.isNotEmpty) const Divider(height: 1),
          for (final track in tracksWithCovers)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Image.file(File(track.coverPath!), fit: BoxFit.cover),
                ),
              ),
              title: Text(track.displayTitle),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref.read(playlistsRepositoryProvider).setCoverFromTrack(playlist.id, track.id);
              },
            ),
        ],
      ),
    ),
  );
}
