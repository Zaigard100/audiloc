import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/profile_session.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/profiles/profiles_store.dart';
import 'features/profiles/initial_profile_name_screen.dart';
import 'services/playback/audiloc_audio_handler.dart';
import 'services/playback/media_kit_player_service.dart';

/// The app's root widget and the owner of the current profile session's
/// lifecycle (docs/adr/0013-account-profiles.md) — everything below it
/// (`UncontrolledProviderScope` and down) belongs to whichever profile is
/// currently active, and gets torn down and rebuilt whole when the user
/// switches profiles.
///
/// The player and its `audio_service` wiring are created once here and
/// live for the whole process, independent of profile switches — they're
/// UI/hardware plumbing, not data that belongs to one profile.
class AudilocApp extends StatefulWidget {
  const AudilocApp({super.key});

  @override
  State<AudilocApp> createState() => _AudilocAppState();
}

class _AudilocAppState extends State<AudilocApp> {
  late final MediaKitPlayerService _playerService;
  ProfilesStore? _profilesStore;
  ProfileSessionHandle? _session;
  bool _needsInitialProfileName = false;

  @override
  void initState() {
    super.initState();
    _playerService = MediaKitPlayerService();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // Notification/lock-screen controls + headset buttons (ТЗ п.3).
    // Android only: audio_service has no Linux/Windows platform
    // implementation, and calling AudioService.init on a platform without
    // one throws rather than no-op-ing. Done once here, not per profile —
    // it just mirrors whatever the (also process-lifetime) player is
    // doing, regardless of which profile that happens to be.
    if (Platform.isAndroid) {
      await AudioService.init(
        builder: () => AudilocAudioHandler(_playerService),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.audiloc.audiloc.channel.audio',
          androidNotificationChannelName: 'AudiLoc',
          androidNotificationOngoing: true,
        ),
      );
    }

    final appSupportDir = await getApplicationSupportDirectory();
    final store = ProfilesStore(appSupportDir);
    if (!mounted) return;
    setState(() => _profilesStore = store);

    // A genuinely fresh install (nothing to migrate either) — ask for a
    // name instead of silently calling it "Профиль 1". Anyone upgrading
    // from before profiles existed skips this entirely: their library
    // gets migrated and reopened with zero prompts, same as always.
    if (await store.needsInitialSetup()) {
      if (!mounted) return;
      setState(() => _needsInitialProfileName = true);
      return;
    }

    await _openProfile(await store.resolveActiveProfileId());
  }

  Future<void> _createInitialProfile(String name) async {
    final profile = await _profilesStore!.create(name);
    await _profilesStore!.setActiveProfileId(profile.id);
    if (!mounted) return;
    setState(() => _needsInitialProfileName = false);
    await _openProfile(profile.id);
  }

  Future<void> _openProfile(String profileId) async {
    final session = await openProfileSession(
      profileId: profileId,
      playerService: _playerService,
      profilesStore: _profilesStore!,
      switchProfile: _switchProfile,
    );
    if (!mounted) {
      await session.close();
      return;
    }
    setState(() => _session = session);
  }

  Future<void> _switchProfile(String profileId) async {
    final old = _session;
    setState(() => _session = null); // brief loading state during the swap
    // The old profile's queue is meaningless once its library is gone —
    // stop rather than leave the player pointed at now-invisible tracks.
    await _playerService.setQueue(const []);
    if (old != null) await old.close();
    await _profilesStore!.setActiveProfileId(profileId);
    await _openProfile(profileId);
  }

  @override
  void dispose() {
    unawaited(_session?.close());
    unawaited(_playerService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_needsInitialProfileName) {
      return MaterialApp(
        title: 'AudiLoc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: InitialProfileNameScreen(onSubmit: _createInitialProfile),
      );
    }

    final session = _session;
    if (session == null) {
      return MaterialApp(
        title: 'AudiLoc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return UncontrolledProviderScope(
      container: session.container,
      child: MaterialApp.router(
        title: 'AudiLoc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        routerConfig: appRouter,
      ),
    );
  }
}
