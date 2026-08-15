import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import 'favorites_screen.dart';
import 'providers/playlists_providers.dart';
import 'trash_screen.dart';
import 'widgets/playlist_actions_sheet.dart';

/// Плейлисты tab: a grid of square cards, not a list — "Избранное" and
/// "Удалённые" are pinned first as special cards (docs/adr/0014), then
/// the user's own playlists.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navPlaylists)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPlaylist(context, ref),
        child: const Icon(Icons.add),
      ),
      body: playlistsAsync.when(
        data: (playlists) => GridView(
          padding: const EdgeInsets.all(12),
          // A fixed column count made tiles balloon to the width of the
          // window on desktop — a max extent instead caps how big a tile
          // can get and just adds more columns as the window widens.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          children: [
            _PlaylistTile(
              label: l10n.favoritesTitle,
              icon: Icons.favorite,
              color: AppTheme.accent,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
            _PlaylistTile(
              label: l10n.trashTitle,
              icon: Icons.delete_outline,
              color: AppTheme.surfaceHigh,
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashScreen())),
            ),
            for (final playlist in playlists)
              _PlaylistTile(
                label: playlist.name,
                icon: Icons.queue_music,
                color: AppTheme.surfaceHigh,
                coverPath: playlist.coverPath,
                onTap: () => context.push('/playlists/${playlist.id}', extra: playlist),
                // Right-click on desktop opens the same menu as long-press
                // — see docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md.
                // Only user-created playlists get this menu — "Избранное"/
                // "Удалённые" above are fixed, built-in views.
                onLongPress: () => showPlaylistActionsSheet(context, ref, playlist),
              ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(l10n.commonErrorPrefix(error))),
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.playlistCreateTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.fieldName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.commonCreate),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(playlistsRepositoryProvider).create(name);
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.coverPath,
    this.onLongPress,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// A resolved local image path (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md)
  /// — when set, replaces [icon] entirely. Only ever non-null for a
  /// user-created playlist that's had a cover picked for it.
  final String? coverPath;

  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isAccent = color == AppTheme.accent;
    final tile = Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: coverPath != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(coverPath!), fit: BoxFit.cover),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 40, color: isAccent ? Colors.white : AppTheme.onSurfaceMuted),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isAccent ? Colors.white : null,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );

    if (onLongPress == null) return tile;
    return GestureDetector(onSecondaryTap: onLongPress, child: tile);
  }
}
