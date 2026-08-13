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
import 'data/profiles/profiles_store.dart';
import 'features/profiles/initial_profile_name_screen.dart';
import 'services/playback/audiloc_audio_handler.dart';
import 'services/playback/media_kit_player_service.dart';
import 'services/sync/pairing/pairing_models.dart';

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

  /// Set while this device is a placeholder profile waiting to be paired
  /// into an existing one (the "Ждать сопряжения" button — same-owner,
  /// second-device scenario). Drives the banner in [build], and — via
  /// `canJoinDifferentProfile` passed to [openProfileSession] — is the
  /// *only* condition under which a mismatched-hash pairing request is
  /// even shown to the user rather than auto-declined; see
  /// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md. Approving
  /// such a request switches this device onto the requester's profile
  /// (see [_joinProfileForPairing]), clearing this flag as a side effect
  /// of [_switchProfile].
  bool _awaitingProfileAdoption = false;

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

  /// "Это моё второе устройство" — creates an empty placeholder profile
  /// and switches to it, with `_awaitingProfileAdoption` set. That flag is
  /// what makes `PairingService` let a mismatched-hash request through to
  /// the UI at all (see `canJoinDifferentProfile` on [openProfileSession])
  /// — approving it then finds the placeholder's hash doesn't match the
  /// requester's, and switches this device onto (a fresh local copy of)
  /// the requester's profile — docs/adr/0017.
  ///
  /// Reachable two ways, handled by the same method since only the
  /// "is there already a session to tear down first" part differs:
  /// [InitialProfileNameScreen] on a genuinely fresh install (no session
  /// yet — nothing to close), and the profile switcher at any later point
  /// (`waitForPairingProvider`, when other profiles already exist and the
  /// user wants to link a *new* device to one of them instead of creating
  /// another empty profile by hand).
  Future<void> _waitForPairing() async {
    final profile = await _profilesStore!.create('Новое устройство');
    if (_session != null) {
      await _switchProfile(profile.id);
    } else {
      await _profilesStore!.setActiveProfileId(profile.id);
      if (!mounted) return;
      setState(() => _needsInitialProfileName = false);
      await _openProfile(profile.id);
    }
    if (!mounted) return;
    setState(() => _awaitingProfileAdoption = true);
  }

  /// Handed to [openProfileSession] as `joinProfileForPairing` — called
  /// by `PairingService.approve()` when an incoming request's profile
  /// doesn't match the one currently active (only reachable while
  /// `_awaitingProfileAdoption` is true — docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md).
  /// Finds (or creates) a local copy of the requester's profile, switches
  /// onto it if it isn't already active, then re-runs `approve` on the
  /// *new* session's `PairingService` — the switch alone is what turns
  /// "two independent libraries" into "download the requester's library
  /// into this now-empty-or-matching profile" via the ordinary CRDT sync
  /// that follows, and re-approving (rather than pairing directly) is
  /// what makes sure the response the requester gets carries this
  /// device's real, permanent identity in the new database — not the
  /// placeholder identity that's about to stop existing (see
  /// `PairingService.approve`'s doc for why that distinction matters).
  Future<void> _joinProfileForPairing(IncomingPairingRequest request) async {
    final store = _profilesStore!;
    final target = await store.findByHash(request.profileHash) ??
        await store.create(request.fromName, profileHash: request.profileHash);

    // Captured *before* switching — _switchProfile clears this flag as
    // one of its first steps, so this is the only place that can still
    // tell whether the profile we're about to leave was the "Ждать
    // сопряжения" placeholder (see [_waitForPairing]) rather than some
    // profile the user was otherwise actually using.
    final wasPlaceholder = _awaitingProfileAdoption;
    final oldProfileId = _session?.container.read(currentProfileProvider).id;
    if (oldProfileId != target.id) {
      await _switchProfile(target.id);
      // The placeholder has done its one job — it exists solely to wait
      // for exactly this moment. Left registered, it would sit in the
      // switcher forever as a permanently-empty, unreachable "Новое
      // устройство" nobody asked to keep (docs/adr/0021-clean-up-placeholder-profile-after-join.md).
      if (wasPlaceholder && oldProfileId != null) {
        await store.delete(oldProfileId);
      }
    }

    final session = _session;
    if (session == null) return; // shouldn't happen, but never crash on it
    await session.container.read(pairingServiceProvider).approve(request);
  }

  Future<void> _openProfile(String profileId) async {
    final session = await openProfileSession(
      profileId: profileId,
      playerService: _playerService,
      profilesStore: _profilesStore!,
      switchProfile: _switchProfile,
      joinProfileForPairing: _joinProfileForPairing,
      canJoinDifferentProfile: () async => _awaitingProfileAdoption,
      waitForPairing: _waitForPairing,
    );
    if (!mounted) {
      await session.close();
      return;
    }
    setState(() => _session = session);
  }

  Future<void> _switchProfile(String profileId) async {
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
