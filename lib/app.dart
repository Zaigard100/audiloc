import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/profile_session.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/models/device.dart';
import 'data/profiles/profiles_store.dart';
import 'features/devices/providers/devices_providers.dart';
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

  /// Set while this device is a placeholder profile waiting to adopt the
  /// name of whichever device it gets paired with (the "Ждать сопряжения"
  /// button — same-owner, second-device scenario, see
  /// docs/adr/0013-account-profiles.md). Drives the banner in [build] and
  /// gates the listener in [_watchForProfileAdoption].
  bool _awaitingProfileAdoption = false;
  ProviderSubscription<AsyncValue<List<Device>>>? _adoptionSubscription;

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

  /// "Это моё второе устройство" (see `InitialProfileNameScreen`'s doc
  /// comment for why this is a placeholder-that-adopts-a-name rather than
  /// literally joining an existing profile). Opens a session normally,
  /// then starts [_watchForProfileAdoption] to pick up the paired
  /// device's name the moment pairing actually completes.
  Future<void> _waitForPairing() async {
    final profile = await _profilesStore!.create('Новое устройство');
    await _profilesStore!.setActiveProfileId(profile.id);
    if (!mounted) return;
    setState(() {
      _needsInitialProfileName = false;
      _awaitingProfileAdoption = true;
    });
    await _openProfile(profile.id);
    _watchForProfileAdoption();
  }

  /// Watches this (placeholder) profile's paired-devices list; the moment
  /// it stops being empty, pairing succeeded (through the ordinary
  /// confirm-on-both-sides flow — nothing here changes that, see
  /// docs/adr/0011-mutual-pairing-confirmation.md) — adopt that peer's
  /// name as this profile's own and stop waiting.
  void _watchForProfileAdoption() {
    final session = _session;
    if (session == null) return;
    final selfId = session.container.read(selfDeviceProvider).id;
    _adoptionSubscription = session.container.listen<AsyncValue<List<Device>>>(
      knownDevicesProvider,
      (previous, next) {
        final peer = _firstPeer(next.value, selfId);
        if (peer != null) unawaited(_adoptProfileName(peer.name));
      },
      // Covers a pairing response that already arrived in the gap between
      // the session becoming usable and this listener attaching.
      fireImmediately: true,
    );
  }

  Device? _firstPeer(List<Device>? devices, String selfId) {
    if (devices == null) return null;
    for (final device in devices) {
      if (device.id != selfId) return device;
    }
    return null;
  }

  Future<void> _adoptProfileName(String name) async {
    _adoptionSubscription?.close();
    _adoptionSubscription = null;
    final session = _session;
    if (session == null) return;
    await applyActiveProfileRename(
      profilesStore: _profilesStore!,
      deviceIdentity: session.container.read(deviceIdentityServiceProvider),
      current: session.container.read(currentProfileProvider),
      setCurrentProfile: (p) => session.container.read(currentProfileProvider.notifier).state = p,
      name: name,
    );
    if (!mounted) return;
    setState(() => _awaitingProfileAdoption = false);
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
    _adoptionSubscription?.close();
    _adoptionSubscription = null;
    if (_awaitingProfileAdoption) setState(() => _awaitingProfileAdoption = false);
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
    _adoptionSubscription?.close();
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
        home: InitialProfileNameScreen(onSubmit: _createInitialProfile, onWaitForPairing: _waitForPairing),
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
        builder: (context, child) {
          if (!_awaitingProfileAdoption || child == null) return child ?? const SizedBox.shrink();
          // The app underneath is fully usable while this shows — pairing
          // just hasn't completed yet (docs/adr/0013-account-profiles.md).
          return Column(
            children: [
              Material(
                color: AppTheme.accent,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Ждём сопряжения со вторым устройством — подтвердите на вкладке «Устройства»',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => appRouter.go('/devices'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('Устройства'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          );
        },
      ),
    );
  }
}
