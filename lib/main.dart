import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/db/audiloc_database.dart';
import 'data/repositories/devices_repository.dart';
import 'services/playback/audiloc_audio_handler.dart';
import 'services/playback/media_kit_player_service.dart';
import 'services/sync/device_identity_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final database = await AudilocDatabase.open();
  final devicesRepository = DevicesRepository(database.crdt);
  final identity = DeviceIdentityService(database, devicesRepository);
  final selfDevice = await identity.ensureSelfDevice();

  // Created here rather than left to playerServiceProvider's own default so
  // the same instance can be handed to AudilocAudioHandler below — the UI
  // and the OS media session must be driving (and observing) one player,
  // not two independent ones.
  final playerService = MediaKitPlayerService();

  // Notification/lock-screen controls + headset buttons (ТЗ п.3). Android
  // only: audio_service has no Linux/Windows platform implementation (see
  // AudilocAudioHandler's doc comment), and calling AudioService.init on a
  // platform without one throws rather than no-op-ing.
  if (Platform.isAndroid) {
    await AudioService.init(
      builder: () => AudilocAudioHandler(playerService),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.audiloc.audiloc.channel.audio',
        androidNotificationChannelName: 'AudiLoc',
        androidNotificationOngoing: true,
      ),
    );
  }

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(database),
    selfDeviceProvider.overrideWithValue(selfDevice),
    playerServiceProvider.overrideWithValue(playerService),
  ]);

  // LAN discovery + metadata sync + file transfer + pairing all start in
  // the background and never block the UI (ТЗ п.7: offline-first, sync is
  // a bonus, not a gate).
  unawaited(container.read(syncOrchestratorProvider).start(metadataSyncPort));
  unawaited(container.read(pairingServerProvider).start());
  // Forces PairingService to exist now rather than whenever some widget
  // first reads it — its constructor is what subscribes to the (broadcast,
  // so no-replay) responses stream, and a pairing response arriving before
  // anyone's listening would otherwise be silently lost.
  container.read(pairingServiceProvider);
  unawaited(() async {
    // Repair pre-existing local tracks/covers that predate track_locations
    // (or this device's own row in it) before anything starts treating
    // them as missing — see TracksRepository.backfillLocalFileLocations
    // and .backfillLocalCovers.
    final tracksRepository = container.read(tracksRepositoryProvider);
    await tracksRepository.backfillLocalFileLocations();
    await tracksRepository.backfillLocalCovers(await container.read(coverCacheDirProvider.future));
    await container.read(fileTransferServerProvider).start();
    final fileSync = await container.read(fileSyncServiceProvider.future);
    fileSync.start();
    final coverSync = await container.read(coverSyncServiceProvider.future);
    coverSync.start();
  }());

  runApp(UncontrolledProviderScope(container: container, child: const AudilocApp()));
}
