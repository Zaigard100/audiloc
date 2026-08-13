import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/db/audiloc_database.dart';
import '../data/profiles/profile.dart';
import '../data/profiles/profiles_store.dart';
import '../data/repositories/devices_repository.dart';
import '../services/playback/player_service.dart';
import '../services/sync/device_identity_service.dart';
import '../services/sync/pairing/pairing_models.dart';
import 'providers.dart';

/// Everything that depends on which profile is active: its database, CRDT
/// identity, and the `ProviderContainer` the rest of the app reads from.
/// Opened once at startup (from `AudilocApp`) and again on every profile
/// switch — see docs/adr/0013-account-profiles.md.
class ProfileSessionHandle {
  ProfileSessionHandle._(this.container, this._database, this._backgroundWork);

  final ProviderContainer container;
  final AudilocDatabase _database;

  /// The startup-time backfill scans + starting the file/cover sync
  /// watchers (see [openProfileSession]) — not awaited by
  /// [openProfileSession] itself (no reason to make the UI wait on it),
  /// but [close] needs to know it has actually finished before tearing
  /// anything down, or it can still be mid-flight setting up a new
  /// subscription against a service `close` already disposed.
  final Future<void> _backgroundWork;

  /// Tears everything down in the order that matters: first, whatever
  /// startup work was still running in the background — otherwise it can
  /// still be setting things up while the rest of this runs underneath
  /// it. Then the network servers bound to fixed, reused ports (metadata
  /// sync, file transfer, pairing), stopped and *awaited* in turn, so a
  /// session opened right after this one returns can rebind those same
  /// ports immediately. `ProviderContainer.dispose()` alone doesn't
  /// guarantee that — Riverpod fires `ref.onDispose` callbacks without
  /// awaiting whatever `Future` they return, so relying on it here would
  /// leave a race where the new session's `HttpServer.bind` could lose to
  /// the old one still closing.
  ///
  /// Every step is additionally bounded by [_step] — belt-and-braces on
  /// top of `MetadataSyncService.dispose()` already internally bounding
  /// its own risky part (waiting on a real peer's close handshake, see
  /// its doc comment): switching profiles must never be able to hang the
  /// UI forever no matter which step turns out to be the slow one.
  Future<void> close() async {
    await _step('backgroundWork', () => _backgroundWork);
    await _step('pairingService', () => container.read(pairingServiceProvider).dispose());
    await _step('pairingServer', () => container.read(pairingServerProvider).dispose());
    await _step('shareServer', () => container.read(shareServerProvider).dispose());
    await _step('fileTransferServer', () => container.read(fileTransferServerProvider).dispose());
    await _step(
        'fileSyncService', () async => (await container.read(fileSyncServiceProvider.future)).dispose());
    await _step('coverSyncService',
        () async => (await container.read(coverSyncServiceProvider.future)).dispose());
    await _step('syncOrchestrator', () => container.read(syncOrchestratorProvider).dispose());
    await _step('metadataSyncService', () => container.read(metadataSyncServiceProvider).dispose());
    await _step('discoveryService', () => container.read(discoveryServiceProvider).dispose());
    container.dispose();
    await _database.close();
  }

  Future<void> _step(String name, Future<void> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 3));
    } catch (_) {
      // A stuck step (typically a network teardown a peer never
      // acknowledged) must never make switching profiles hang forever —
      // better to move on, even if that step's resources leak until the
      // OS reclaims them, than freeze the UI.
    }
  }
}

/// Opens the database and starts every background service for
/// [profileId] — the same sequence `main()` used to run once, unconditionally,
/// before profiles existed. [switchProfile] is threaded through as a
/// provider override so any widget (e.g. the profile switcher) can trigger
/// a switch without needing a reference to `AudilocApp` itself.
Future<ProfileSessionHandle> openProfileSession({
  required String profileId,
  required PlayerService playerService,
  required ProfilesStore profilesStore,
  required Future<void> Function(String profileId) switchProfile,
  required Future<void> Function(IncomingPairingRequest) joinProfileForPairing,
  required Future<bool> Function() canJoinDifferentProfile,
  Future<String> Function() platformLabel = platformDeviceLabel,
}) async {
  final profiles = await profilesStore.list();
  final profile = profiles.firstWhere((p) => p.id == profileId);
  final profileDir = profilesStore.profileDir(profileId);

  final database = await AudilocDatabase.open(path: p.join(profileDir.path, 'audiloc.db'));
  final devicesRepository = DevicesRepository(database.crdt);
  final identity = DeviceIdentityService(database, devicesRepository);
  var selfDevice = await identity.ensureSelfDevice();
  // The device name peers see is always "<profile name> (<platform
  // label>)" (docs/adr/0013-account-profiles.md,
  // docs/adr/0016-device-label.md) — resynced on every open in case the
  // profile was renamed while this device wasn't the active session.
  final desiredName = composeDeviceName(profile.name, await platformLabel());
  if (selfDevice.name != desiredName) {
    await identity.rename(desiredName);
    selfDevice = (await devicesRepository.byId(identity.deviceId))!;
  }

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(database),
    selfDeviceProvider.overrideWithValue(selfDevice),
    playerServiceProvider.overrideWithValue(playerService),
    profileDirProvider.overrideWithValue(profileDir),
    currentProfileProvider.overrideWith((ref) => profile),
    profilesStoreProvider.overrideWithValue(profilesStore),
    switchProfileProvider.overrideWithValue(switchProfile),
    joinProfileForPairingProvider.overrideWithValue(joinProfileForPairing),
    canJoinDifferentProfileProvider.overrideWithValue(canJoinDifferentProfile),
  ]);

  // The three fixed-port *bind* calls are awaited — deliberately *not*
  // `unawaited`, unlike everything else below. `close()` assumes these
  // ports are actually bound by the time it runs (that's what lets a
  // profile switch safely rebind them right after); if `openProfileSession`
  // returned before that were true, closing a session moments after
  // opening it — exactly what a fast profile switch does — could tear
  // down a server that hadn't finished starting yet, leaving the port
  // to bind (and collide with the next session) at some unpredictable
  // later moment instead. The bind itself is a local syscall, not a
  // network round trip, so this costs microseconds, not a UI stall.
  //
  // `metadataSyncService.startServer()` is called directly (idempotent —
  // `SyncOrchestrator.start()` below calls it again and just no-ops) so it
  // can be awaited on its own, *without* waiting on mDNS
  // advertising/discovery too: that part talks to a platform plugin and
  // can fail or hang for reasons that have nothing to do with this
  // profile's data being usable (ТЗ п.7 — sync is a bonus, not a gate;
  // there's no reason a flaky mDNS environment should block opening the
  // library).
  await container.read(metadataSyncServiceProvider).startServer();
  unawaited(container.read(syncOrchestratorProvider).start(metadataSyncPort));
  await container.read(pairingServerProvider).start();
  await container.read(shareServerProvider).start();
  await container.read(fileTransferServerProvider).start();
  // Forces PairingService to exist now rather than whenever some widget
  // first reads it — its constructor is what subscribes to the (broadcast,
  // so no-replay) responses stream, and a pairing response arriving before
  // anyone's listening would otherwise be silently lost.
  container.read(pairingServiceProvider);
  // Not awaited — no reason to make the UI wait on it — but the Future is
  // kept so `close()` can wait for it later. See
  // `ProfileSessionHandle._backgroundWork`.
  final backgroundWork = () async {
    // Repair pre-existing local tracks/covers that predate track_locations
    // (or this device's own row in it) before anything starts treating
    // them as missing — see TracksRepository.backfillLocalFileLocations
    // and .backfillLocalCovers.
    final tracksRepository = container.read(tracksRepositoryProvider);
    await tracksRepository.backfillLocalFileLocations();
    await tracksRepository.backfillLocalCovers(await container.read(coverCacheDirProvider.future));
    final fileSync = await container.read(fileSyncServiceProvider.future);
    fileSync.start();
    final coverSync = await container.read(coverSyncServiceProvider.future);
    coverSync.start();
  }();

  return ProfileSessionHandle._(container, database, backgroundWork);
}

/// Renames the *currently active* profile — its entry in [profilesStore],
/// its self-device row (so the new `"<name> (<platform label>)"` is what
/// peers see, keeping the invariant from docs/adr/0013-account-profiles.md
/// and docs/adr/0016-device-label.md), and [currentProfileProvider]'s live
/// state so the UI reflects it immediately without reopening the session.
/// Used by the profile switcher's manual rename.
///
/// Takes already-resolved dependencies rather than a `Ref`/`ProviderContainer`
/// directly: callers reach this from both a `WidgetRef` (the switcher, a
/// widget) and a raw `ProviderContainer` (`AudilocApp`, not a widget) —
/// two different types with no common supertype worth introducing for
/// four lines of logic.
Future<Profile> applyActiveProfileRename({
  required ProfilesStore profilesStore,
  required DeviceIdentityService deviceIdentity,
  required Profile current,
  required void Function(Profile) setCurrentProfile,
  required String name,
  Future<String> Function() platformLabel = platformDeviceLabel,
}) async {
  await profilesStore.rename(current.id, name);
  await deviceIdentity.rename(composeDeviceName(name, await platformLabel()));
  final renamed = current.copyWith(name: name);
  setCurrentProfile(renamed);
  return renamed;
}
