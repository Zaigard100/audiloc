import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/db/audiloc_database.dart';
import 'data/repositories/devices_repository.dart';
import 'services/sync/device_identity_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final database = await AudilocDatabase.open();
  final devicesRepository = DevicesRepository(database.crdt);
  final identity = DeviceIdentityService(database, devicesRepository);
  final selfDevice = await identity.ensureSelfDevice();

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(database),
    selfDeviceProvider.overrideWithValue(selfDevice),
  ]);

  // LAN discovery + metadata sync + file transfer all start in the
  // background and never block the UI (ТЗ п.7: offline-first, sync is a
  // bonus, not a gate).
  unawaited(container.read(syncOrchestratorProvider).start(metadataSyncPort));
  unawaited(() async {
    // Repair pre-existing local tracks that predate track_locations (or
    // this device's own row in it) before anything starts treating them
    // as missing — see TracksRepository.backfillLocalFileLocations.
    await container.read(tracksRepositoryProvider).backfillLocalFileLocations();
    await container.read(fileTransferServerProvider).start();
    final fileSync = await container.read(fileSyncServiceProvider.future);
    fileSync.start();
  }());

  runApp(UncontrolledProviderScope(container: container, child: const AudilocApp()));
}
