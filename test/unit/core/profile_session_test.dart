import 'dart:async';
import 'dart:io';

import 'package:audiloc/core/profile_session.dart';
import 'package:audiloc/core/providers.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/profiles/profile.dart';
import 'package:audiloc/data/profiles/profiles_store.dart';
import 'package:audiloc/features/player/models/playback_shortcuts_settings.dart';
import 'package:audiloc/services/playback/player_service.dart';
import 'package:audiloc/services/sync/pairing/pairing_models.dart';
import 'package:flutter/material.dart' show Locale, ThemeMode;
import 'package:flutter_test/flutter_test.dart';

/// `openProfileSession` doesn't touch playback beyond clearing the queue
/// on switch — these tests are about port teardown, not playback, so a
/// no-op stands in fine.
class _NoopPlayerService implements PlayerService {
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<PlaybackPositionState> get positionStream => const Stream.empty();
  @override
  Stream<Track?> get currentTrackStream => const Stream.empty();
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  bool get isPlaying => false;
  @override
  Track? get currentTrack => null;
  @override
  Duration get position => Duration.zero;
  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0, bool autoPlay = true}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> playOrPause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _noopSwitch(String profileId) async {}
Future<void> _noopJoin(IncomingPairingRequest request) async {}
Future<String> _testPlatformLabel() async => 'TestOS';
Future<bool> _noopCanJoin() async => false;
Future<void> _noopWaitForPairing() async {}
Future<void> _noopChangeLanguage(Locale? locale) async {}
Future<void> _noopChangeThemeMode(ThemeMode mode) async {}
Future<void> _noopEraseAllData() async {}
Future<void> _noopChangePlaybackShortcutsSettings(PlaybackShortcutsSettings settings) async {}

void main() {
  test(
      'closing a profile session fully releases its network ports before returning, so a '
      'second session can immediately rebind them (regression: ProviderContainer.dispose() '
      'alone does not await the Futures returned by async ref.onDispose callbacks — see '
      'docs/adr/0013-account-profiles.md)', () async {
    // Deliberately uses the app's *real* metadataSyncPort/fileTransferPort/
    // pairingPort (unlike other test files, which pick distinct ports to
    // avoid colliding with a real running app) — the whole point here is
    // proving those exact ports get released, not just "some" ports.
    final appSupportDir = await Directory.systemTemp.createTemp('audiloc_session_');
    addTearDown(() => appSupportDir.delete(recursive: true));
    final store = ProfilesStore(appSupportDir);
    final profile = await store.create('Test Profile');
    final player = _NoopPlayerService();

    final first = await openProfileSession(
      profileId: profile.id,
      playerService: player,
      profilesStore: store,
      switchProfile: _noopSwitch,
      joinProfileForPairing: _noopJoin,
      canJoinDifferentProfile: _noopCanJoin,
      waitForPairing: _noopWaitForPairing,
      changeLanguage: _noopChangeLanguage,
      initialLocale: null,
      changeThemeMode: _noopChangeThemeMode,
      initialThemeMode: ThemeMode.system,
      eraseAllData: _noopEraseAllData,
      changePlaybackShortcutsSettings: _noopChangePlaybackShortcutsSettings,
      initialPlaybackShortcutsSettings: const PlaybackShortcutsSettings(),
      platformLabel: _testPlatformLabel,
    );
    await first.close();

    // If teardown weren't properly sequential/awaited, this would throw
    // (address already in use) on whichever port didn't actually free up
    // in time.
    final second = await openProfileSession(
      profileId: profile.id,
      playerService: player,
      profilesStore: store,
      switchProfile: _noopSwitch,
      joinProfileForPairing: _noopJoin,
      canJoinDifferentProfile: _noopCanJoin,
      waitForPairing: _noopWaitForPairing,
      changeLanguage: _noopChangeLanguage,
      initialLocale: null,
      changeThemeMode: _noopChangeThemeMode,
      initialThemeMode: ThemeMode.system,
      eraseAllData: _noopEraseAllData,
      changePlaybackShortcutsSettings: _noopChangePlaybackShortcutsSettings,
      initialPlaybackShortcutsSettings: const PlaybackShortcutsSettings(),
      platformLabel: _testPlatformLabel,
    );
    await second.close();
  });

  test(
      "the self-device's name is always \"<profile name> (<platform label>)\" "
      "(docs/adr/0013-account-profiles.md, docs/adr/0016-device-label.md — this "
      "is what makes devices sharing a profile distinguishable in the switcher)",
      () async {
    final appSupportDir = await Directory.systemTemp.createTemp('audiloc_session_name_');
    addTearDown(() => appSupportDir.delete(recursive: true));
    final store = ProfilesStore(appSupportDir);
    final profile = await store.create('Мама');
    final player = _NoopPlayerService();

    final session = await openProfileSession(
      profileId: profile.id,
      playerService: player,
      profilesStore: store,
      switchProfile: _noopSwitch,
      joinProfileForPairing: _noopJoin,
      canJoinDifferentProfile: _noopCanJoin,
      waitForPairing: _noopWaitForPairing,
      changeLanguage: _noopChangeLanguage,
      initialLocale: null,
      changeThemeMode: _noopChangeThemeMode,
      initialThemeMode: ThemeMode.system,
      eraseAllData: _noopEraseAllData,
      changePlaybackShortcutsSettings: _noopChangePlaybackShortcutsSettings,
      initialPlaybackShortcutsSettings: const PlaybackShortcutsSettings(),
      platformLabel: _testPlatformLabel,
    );
    addTearDown(session.close);

    expect(session.container.read(selfDeviceProvider).name, 'Мама (TestOS)');
  });

  test(
      'a rename applied while a profile was not the active session is picked up the '
      'next time that profile is opened', () async {
    final appSupportDir = await Directory.systemTemp.createTemp('audiloc_session_rename_');
    addTearDown(() => appSupportDir.delete(recursive: true));
    final store = ProfilesStore(appSupportDir);
    final profile = await store.create('Старое имя');
    final player = _NoopPlayerService();

    final first = await openProfileSession(
      profileId: profile.id,
      playerService: player,
      profilesStore: store,
      switchProfile: _noopSwitch,
      joinProfileForPairing: _noopJoin,
      canJoinDifferentProfile: _noopCanJoin,
      waitForPairing: _noopWaitForPairing,
      changeLanguage: _noopChangeLanguage,
      initialLocale: null,
      changeThemeMode: _noopChangeThemeMode,
      initialThemeMode: ThemeMode.system,
      eraseAllData: _noopEraseAllData,
      changePlaybackShortcutsSettings: _noopChangePlaybackShortcutsSettings,
      initialPlaybackShortcutsSettings: const PlaybackShortcutsSettings(),
      platformLabel: _testPlatformLabel,
    );
    await first.close();

    await store.rename(profile.id, 'Новое имя');

    final second = await openProfileSession(
      profileId: profile.id,
      playerService: player,
      profilesStore: store,
      switchProfile: _noopSwitch,
      joinProfileForPairing: _noopJoin,
      canJoinDifferentProfile: _noopCanJoin,
      waitForPairing: _noopWaitForPairing,
      changeLanguage: _noopChangeLanguage,
      initialLocale: null,
      changeThemeMode: _noopChangeThemeMode,
      initialThemeMode: ThemeMode.system,
      eraseAllData: _noopEraseAllData,
      changePlaybackShortcutsSettings: _noopChangePlaybackShortcutsSettings,
      initialPlaybackShortcutsSettings: const PlaybackShortcutsSettings(),
      platformLabel: _testPlatformLabel,
    );
    addTearDown(second.close);

    expect(second.container.read(selfDeviceProvider).name, 'Новое имя (TestOS)');
  });

  test(
      'applyActiveProfileRename updates the registry, the self-device row, and the live '
      'state in one call — used by the profile switcher\'s manual rename', () async {
    final appSupportDir = await Directory.systemTemp.createTemp('audiloc_session_apply_rename_');
    addTearDown(() => appSupportDir.delete(recursive: true));
    final store = ProfilesStore(appSupportDir);
    final profile = await store.create('Старое имя');
    final player = _NoopPlayerService();

    final session = await openProfileSession(
      profileId: profile.id,
      playerService: player,
      profilesStore: store,
      switchProfile: _noopSwitch,
      joinProfileForPairing: _noopJoin,
      canJoinDifferentProfile: _noopCanJoin,
      waitForPairing: _noopWaitForPairing,
      changeLanguage: _noopChangeLanguage,
      initialLocale: null,
      changeThemeMode: _noopChangeThemeMode,
      initialThemeMode: ThemeMode.system,
      eraseAllData: _noopEraseAllData,
      changePlaybackShortcutsSettings: _noopChangePlaybackShortcutsSettings,
      initialPlaybackShortcutsSettings: const PlaybackShortcutsSettings(),
      platformLabel: _testPlatformLabel,
    );
    addTearDown(session.close);

    Profile? updatedState;
    final renamed = await applyActiveProfileRename(
      profilesStore: store,
      deviceIdentity: session.container.read(deviceIdentityServiceProvider),
      current: profile,
      setCurrentProfile: (p) => updatedState = p,
      name: 'Новое имя',
      platformLabel: _testPlatformLabel,
    );

    expect(renamed.name, 'Новое имя');
    expect(updatedState?.name, 'Новое имя');
    expect((await store.list()).single.name, 'Новое имя');
    final selfId = session.container.read(selfDeviceProvider).id;
    final selfDeviceRow = await session.container.read(devicesRepositoryProvider).byId(selfId);
    expect(selfDeviceRow?.name, 'Новое имя (TestOS)');
  });
}
