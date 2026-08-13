import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/audiloc_database.dart';
import '../data/models/device.dart';
import '../data/repositories/devices_repository.dart';
import '../data/repositories/favorites_repository.dart';
import '../data/repositories/playlists_repository.dart';
import '../data/repositories/tracks_repository.dart';
import '../services/dedupe/dedupe_service.dart';
import '../services/library_import/library_import_service.dart';
import '../services/library_import/tag_reader.dart';
import '../services/playback/media_kit_player_service.dart';
import '../services/playback/player_service.dart';
import '../services/settings/secure_settings_service.dart';
import '../services/sync/device_identity_service.dart';
import '../services/sync/discovery/discovery_service.dart';
import '../services/sync/files/syncthing_client.dart';
import '../services/sync/files/syncthing_process_manager.dart';
import '../services/sync/metadata/metadata_sync_service.dart';
import '../services/sync/sync_orchestrator.dart';

/// Central dependency wiring.
///
/// [databaseProvider] and [selfDeviceProvider] are placeholders overridden
/// in `main()` once the async startup sequence (open DB, ensure this
/// device's identity row) has actually completed — see
/// docs/architecture.md for why the app waits on that before `runApp`
/// instead of juggling `FutureProvider` loading states everywhere.
final databaseProvider = Provider<AudilocDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden in main()'),
);

final selfDeviceProvider = Provider<Device>(
  (ref) => throw UnimplementedError('selfDeviceProvider must be overridden in main()'),
);

final tracksRepositoryProvider =
    Provider((ref) => TracksRepository(ref.watch(databaseProvider).crdt));

final favoritesRepositoryProvider =
    Provider((ref) => FavoritesRepository(ref.watch(databaseProvider).crdt));

final playlistsRepositoryProvider =
    Provider((ref) => PlaylistsRepository(ref.watch(databaseProvider).crdt));

final devicesRepositoryProvider =
    Provider((ref) => DevicesRepository(ref.watch(databaseProvider).crdt));

final deviceIdentityServiceProvider = Provider(
  (ref) => DeviceIdentityService(ref.watch(databaseProvider), ref.watch(devicesRepositoryProvider)),
);

final playerServiceProvider = Provider<PlayerService>((ref) {
  final service = MediaKitPlayerService();
  ref.onDispose(service.dispose);
  return service;
});

final dedupeServiceProvider = Provider<DedupeService>((ref) => DedupeService());

final coverCacheDirProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'covers'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
});

final libraryImportServiceProvider = FutureProvider<LibraryImportService>((ref) async {
  final coverDir = await ref.watch(coverCacheDirProvider.future);
  return LibraryImportService(
    tracksRepository: ref.watch(tracksRepositoryProvider),
    tagReader: TagReader(),
    dedupeService: ref.watch(dedupeServiceProvider),
    deviceId: ref.watch(selfDeviceProvider).id,
    coverCacheDir: coverDir,
  );
});

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final self = ref.watch(selfDeviceProvider);
  final service = DiscoveryService(selfDeviceId: self.id, selfDeviceName: self.name);
  ref.onDispose(service.dispose);
  return service;
});

final metadataSyncServiceProvider = Provider<MetadataSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = MetadataSyncService(crdt: db.crdt);
  ref.onDispose(service.dispose);
  return service;
});

final secureSettingsServiceProvider =
    Provider<SecureSettingsService>((ref) => SecureSettingsService());

/// The Syncthing API key, seeded from secure storage at startup and kept
/// editable from the Devices screen. Null means Syncthing hasn't been
/// paired with AudiLoc's REST client yet.
final syncthingApiKeyProvider = StateProvider<String?>((ref) => null);

final syncthingClientProvider = Provider<SyncthingClient?>((ref) {
  final apiKey = ref.watch(syncthingApiKeyProvider);
  if (apiKey == null || apiKey.isEmpty) return null;
  return SyncthingClient(baseUrl: 'http://127.0.0.1:8384', apiKey: apiKey);
});

final syncthingProcessManagerProvider =
    Provider<SyncthingProcessManager>((ref) => SyncthingProcessManager());

const metadataSyncPort = 8541;

final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  final orchestrator = SyncOrchestrator(
    discoveryService: ref.watch(discoveryServiceProvider),
    metadataSyncService: ref.watch(metadataSyncServiceProvider),
    devicesRepository: ref.watch(devicesRepositoryProvider),
  );
  ref.onDispose(orchestrator.dispose);
  return orchestrator;
});
