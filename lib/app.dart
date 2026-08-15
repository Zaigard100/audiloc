import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/profile_session.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/directory_erase.dart';
import 'data/profiles/profiles_store.dart';
import 'data/settings/app_settings_store.dart';
import 'features/profiles/initial_profile_name_screen.dart';
import 'features/profiles/language_choice_screen.dart';
import 'l10n/l10n.dart';
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

  /// See [_bootstrap]'s doc — `AudioService.init` may only ever run once
  /// per process, but [_bootstrap] itself can now run more than once
  /// (erase-all-data re-triggers it), so this can't just be "did
  /// `_bootstrap` run yet".
  bool _audioServiceInitialized = false;
  ProfilesStore? _profilesStore;
  AppSettingsStore? _settingsStore;
  ProfileSessionHandle? _session;
  bool _needsInitialProfileName = false;

  /// True only before the very first choice has ever been made on this
  /// device (docs/adr/0027-localization.md) — shown even before
  /// [InitialProfileNameScreen], since that screen's own text needs a
  /// language to be in already. Existing installs upgrading into this
  /// version never see it: [_locale] just stays `null` (follow system)
  /// until the user picks one from "О приложении".
  bool _needsLanguageChoice = false;

  /// `null` means "follow the system locale" — [MaterialApp.locale] left
  /// unset does exactly that automatically. Only set once the user makes
  /// an explicit choice (the first-run [LanguageChoiceScreen], or later
  /// from "О приложении"), and persisted via [_settingsStore] so it
  /// survives restarts.
  Locale? _locale;

  /// Persisted via [_settingsStore], defaults to [ThemeMode.system] — see
  /// docs/adr/0028-settings-screen-and-theming.md.
  ThemeMode _themeMode = ThemeMode.system;

  /// Set when [_bootstrap] or [_openProfile] throws — without this, an
  /// exception anywhere in that startup chain (a port still held by a
  /// process that hasn't released it yet, a transient filesystem error,
  /// anything) left [_session] permanently null with nothing to show but
  /// the loading spinner in [build] forever: no error, no retry, nothing
  /// in the UI to tell the user (or this developer) anything went wrong.
  /// See docs/adr/0025-sync-and-discovery-reliability.md.
  Object? _startupError;

  /// The profile id [_openProfile] was last asked to open — kept so
  /// [_retryStartup] can retry the same profile rather than re-deriving
  /// one, which after a mid-switch failure could resolve to the wrong
  /// (old) profile.
  String? _pendingProfileId;

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
    try {
      // Notification/lock-screen controls + headset buttons (ТЗ п.3).
      // Android only: audio_service has no Linux/Windows platform
      // implementation, and calling AudioService.init on a platform without
      // one throws rather than no-op-ing. Done once here, not per profile —
      // it just mirrors whatever the (also process-lifetime) player is
      // doing, regardless of which profile that happens to be. Guarded by
      // [_audioServiceInitialized]: [_bootstrap] itself isn't necessarily
      // once-per-process anymore — "Стереть все данные" re-runs it — but
      // `AudioService.init` asserts it's never called twice in the same
      // process (`assert(_cacheManager == null)`), so a second run must
      // skip this step even though everything else in [_bootstrap] does
      // need to redo its work.
      if (Platform.isAndroid && !_audioServiceInitialized) {
        await AudioService.init(
          builder: () => AudilocAudioHandler(_playerService),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.audiloc.audiloc.channel.audio',
            androidNotificationChannelName: 'AudiLoc',
            androidNotificationOngoing: true,
          ),
        );
        _audioServiceInitialized = true;
      }

      final appSupportDir = await getApplicationSupportDirectory();
      final store = ProfilesStore(appSupportDir);
      final settingsStore = AppSettingsStore(appSupportDir);
      final savedLocale = await settingsStore.languageLocale();
      final savedThemeMode = await settingsStore.themeMode();
      if (!mounted) return;
      setState(() {
        _profilesStore = store;
        _settingsStore = settingsStore;
        _locale = savedLocale;
        _themeMode = savedThemeMode;
      });

      // A genuinely fresh install (nothing to migrate either) — ask for a
      // name instead of silently calling it "Профиль 1". Anyone upgrading
      // from before profiles existed skips this entirely: their library
      // gets migrated and reopened with zero prompts, same as always.
      final needsProfile = await store.needsInitialSetup();
      if (needsProfile && savedLocale == null) {
        // Nothing chosen yet on this device at all — ask which language
        // before anything else, including InitialProfileNameScreen's own
        // text (docs/adr/0027-localization.md).
        if (!mounted) return;
        setState(() => _needsLanguageChoice = true);
        return;
      }
      if (needsProfile) {
        if (!mounted) return;
        setState(() => _needsInitialProfileName = true);
        return;
      }

      await _openProfile(await store.resolveActiveProfileId());
    } catch (error) {
      if (!mounted) return;
      setState(() => _startupError = error);
    }
  }

  /// Bound to the "Повторить" button on the startup-error screen — retries
  /// whatever step failed rather than making the user force-quit and
  /// relaunch, which was previously the only way out of a failed startup.
  Future<void> _retryStartup() async {
    setState(() => _startupError = null);
    final pendingId = _pendingProfileId;
    if (pendingId != null) {
      await _openProfile(pendingId);
    } else {
      await _bootstrap();
    }
  }

  /// Bound to [LanguageChoiceScreen] — persists the choice and moves on to
  /// the profile-name step, same as the rest of the first-run flow.
  Future<void> _chooseLanguage(Locale locale) async {
    await _settingsStore!.setLanguageCode(locale.languageCode);
    if (!mounted) return;
    setState(() {
      _locale = locale;
      _needsLanguageChoice = false;
      _needsInitialProfileName = true;
    });
  }

  /// Bound to the language picker on "О приложении" — the only way to
  /// change language after the first run. `null` clears the explicit
  /// choice and goes back to following the system locale.
  Future<void> _changeLanguage(Locale? locale) async {
    await _settingsStore!.setLanguageCode(locale?.languageCode);
    // Keeps `currentLocaleProvider` in the (unchanged) session container in
    // sync too — that's what the "О приложении" picker itself reads to
    // show which option is selected, and it doesn't get a fresh value for
    // free just from AudilocApp's own setState below (see
    // currentLocaleProvider's doc).
    _session?.container.read(currentLocaleProvider.notifier).state = locale;
    if (!mounted) return;
    setState(() => _locale = locale);
  }

  /// Bound to the theme picker in Settings — same pattern as
  /// [_changeLanguage], see docs/adr/0028-settings-screen-and-theming.md.
  Future<void> _changeThemeMode(ThemeMode mode) async {
    await _settingsStore!.setThemeMode(mode);
    _session?.container.read(currentThemeModeProvider.notifier).state = mode;
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  /// Bound to "Стереть все данные" in Settings, after its own double
  /// confirmation (docs/adr/0028-settings-screen-and-theming.md) — the
  /// caller is a widget inside the very [ProviderContainer] this closes,
  /// so this can't return until well after the `onPressed` that triggered
  /// it has already torn down the tree it's running in; that's fine, the
  /// call itself doesn't touch `context` after `close()`.
  ///
  /// Order matters: [ProfileSessionHandle.close] first (a still-open CRDT
  /// database file inside [appSupportDir] would make deleting it flaky at
  /// best, corrupt the on-disk file at worst), *then* the actual erase,
  /// *then** resetting every field back to the same blank state
  /// [_AudilocAppState] starts in, so [_bootstrap] re-derives a genuinely
  /// fresh install from scratch — same code path an actual first launch
  /// takes, not a special-cased "post-erase" branch that could drift from
  /// it over time.
  Future<void> _eraseAllData() async {
    final appSupportDir = _profilesStore?.appSupportDir;
    final session = _session;
    setState(() => _session = null);
    await _playerService.setQueue(const []);
    if (session != null) await session.close();
    if (appSupportDir != null) await eraseDirectoryBestEffort(appSupportDir);

    if (!mounted) return;
    setState(() {
      _profilesStore = null;
      _settingsStore = null;
      _locale = null;
      _themeMode = ThemeMode.system;
      _needsLanguageChoice = false;
      _needsInitialProfileName = false;
      _awaitingProfileAdoption = false;
      _startupError = null;
      _pendingProfileId = null;
    });
    await _bootstrap();
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
    _pendingProfileId = profileId;
    try {
      final session = await openProfileSession(
        profileId: profileId,
        playerService: _playerService,
        profilesStore: _profilesStore!,
        switchProfile: _switchProfile,
        joinProfileForPairing: _joinProfileForPairing,
        canJoinDifferentProfile: () async => _awaitingProfileAdoption,
        waitForPairing: _waitForPairing,
        changeLanguage: _changeLanguage,
        initialLocale: _locale,
        changeThemeMode: _changeThemeMode,
        initialThemeMode: _themeMode,
        eraseAllData: _eraseAllData,
      );
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _session = session;
        _startupError = null;
        _pendingProfileId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _startupError = error);
    }
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
    if (_needsLanguageChoice) {
      return MaterialApp(
        title: 'AudiLoc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: LanguageChoiceScreen(onChosen: _chooseLanguage),
      );
    }

    if (_needsInitialProfileName) {
      return MaterialApp(
        title: 'AudiLoc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: InitialProfileNameScreen(onSubmit: _createInitialProfile, onWaitForPairing: _waitForPairing),
      );
    }

    final session = _session;
    if (session == null) {
      final error = _startupError;
      return MaterialApp(
        title: 'AudiLoc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: error == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _StartupErrorScreen(error: error, onRetry: _retryStartup),
      );
    }

    return UncontrolledProviderScope(
      container: session.container,
      child: MaterialApp.router(
        title: 'AudiLoc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
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
                        Expanded(
                          child: Text(
                            context.l10n.pairingBannerText,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => appRouter.go('/devices'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: Text(context.l10n.navDevices),
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

/// Shown when [_AudilocAppState._bootstrap]/`_openProfile` fails — a
/// separate widget (rather than inlined in `build()`) purely so it gets
/// its own `BuildContext`, one that's actually a descendant of the
/// `MaterialApp` that provides `AppLocalizations` (`context.l10n` used
/// directly inside `_AudilocAppState.build()` would reach for
/// `Localizations` above where `MaterialApp` installs it, and throw).
class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppTheme.accent),
                const SizedBox(height: 16),
                Text(
                  context.l10n.startupErrorTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: onRetry, child: Text(context.l10n.commonRetry)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
