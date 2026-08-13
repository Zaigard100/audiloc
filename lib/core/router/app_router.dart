import 'package:go_router/go_router.dart';

import '../../data/models/playlist.dart';
import '../../features/playlists/playlist_detail_screen.dart';
import '../../features/shell/app_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/library',
  routes: [
    GoRoute(
      path: '/:tab',
      builder: (context, state) => AppShell(tab: state.pathParameters['tab']!),
    ),
    GoRoute(
      path: '/playlists/:id',
      builder: (context, state) => PlaylistDetailScreen(
        playlistId: state.pathParameters['id']!,
        playlist: state.extra as Playlist?,
      ),
    ),
  ],
);
