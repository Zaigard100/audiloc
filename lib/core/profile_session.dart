import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/db/audiloc_database.dart';
import '../data/profiles/profiles_store.dart';
import '../data/repositories/devices_repository.dart';
import '../services/playback/player_service.dart';
import '../services/sync/device_identity_service.dart';
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
  Future<void> close() async {
    await _backgroundWork.catchError((_) {});
    await container.read(pairingServiceProvider).dispose();
    await container.read(pairingServerProvider).dispose();
    await container.read(fileTransferServerProvider).dispose();
    await (await container.read(fileSyncServiceProvider.future)).dispose();
    await (await container.read(coverSyncServiceProvider.future)).dispose();
    await container.read(syncOrchestratorProvider).dispose();
    await container.read(metadataSyncServiceProvider).dispose();
    await container.read(discoveryServiceProvider).dispose();
    container.dispose();
    await _database.close();
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
}) async {
  final profiles = await profilesStore.list();
  final profile = profiles.firstWhere((p) => p.id == profileId);
  final profileDir = profilesStore.profileDir(profileId);

  final database = await AudilocDatabase.open(path: p.join(profileDir.path, 'audiloc.db'));
  final devicesRepository = DevicesRepository(database.crdt);
  final identity = DeviceIdentityService(database, devicesRepository);
  final selfDevice = await identity.ensureSelfDevice();

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(database),
    selfDeviceProvider.overrideWithValue(selfDevice),
    playerServiceProvider.overrideWithValue(playerService),
    profileDirProvider.overrideWithValue(profileDir),
    currentProfileProvider.overrideWithValue(profile),
    profilesStoreProvider.overrideWithValue(profilesStore),
    switchProfileProvider.overrideWithValue(switchProfile),
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
