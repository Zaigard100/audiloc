import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../services/sync/device_identity_service.dart';
import '../services/sync/discovery/discovery_service.dart';
import '../services/sync/files/cover_sync_service.dart';
import '../services/sync/files/file_sync_service.dart';
import '../services/sync/files/file_transfer_client.dart';
import '../services/sync/files/file_transfer_server.dart';
import '../services/sync/metadata/metadata_sync_service.dart';
import '../services/sync/pairing/pairing_client.dart';
import '../services/sync/pairing/pairing_server.dart';
import '../services/sync/pairing/pairing_service.dart';
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
  final service = MetadataSyncService(
    crdt: db.crdt,
    devicesRepository: ref.watch(devicesRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

const metadataSyncPort = 8541;
const fileTransferPort = 8542;
const pairingPort = 8543;

final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  final orchestrator = SyncOrchestrator(
    discoveryService: ref.watch(discoveryServiceProvider),
    metadataSyncService: ref.watch(metadataSyncServiceProvider),
    devicesRepository: ref.watch(devicesRepositoryProvider),
  );
  ref.onDispose(orchestrator.dispose);
  return orchestrator;
});

/// Where files fetched from peers land — kept inside the app's own
/// storage so no platform-specific public-storage/SAF permissions are
/// needed on Android (ТЗ: приложение должно быть самодостаточным).
/// Manually imported files (via the folder picker) are untouched and stay
/// wherever the user pointed at — this is only for P2P-downloaded copies.
final syncedMusicDirProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'synced_music'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
});

final fileTransferServerProvider = Provider<FileTransferServer>((ref) {
  final server = FileTransferServer(
    tracksRepository: ref.watch(tracksRepositoryProvider),
    port: fileTransferPort,
  );
  ref.onDispose(server.dispose);
  return server;
});

final fileTransferClientProvider = Provider<FileTransferClient>((ref) => FileTransferClient());

/// Watches for tracks known only through synced metadata and fetches them
/// from whichever online peer has the file — see
/// docs/adr/0010-built-in-file-transfer.md.
final fileSyncServiceProvider = FutureProvider<FileSyncService>((ref) async {
  final downloadsDir = await ref.watch(syncedMusicDirProvider.future);
  final service = FileSyncService(
    tracksRepository: ref.watch(tracksRepositoryProvider),
    discoveryService: ref.watch(discoveryServiceProvider),
    client: ref.watch(fileTransferClientProvider),
    downloadsDir: downloadsDir,
    filePort: fileTransferPort,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Watches for tracks whose cover art isn't cached on this device yet and
/// fetches it from whichever online peer has it — see
/// docs/adr/0012-local-cover-paths.md. Reuses `FileTransferServer`'s
/// `/covers/<id>` route on the same port, so no separate port needed.
final coverSyncServiceProvider = FutureProvider<CoverSyncService>((ref) async {
  final coverDir = await ref.watch(coverCacheDirProvider.future);
  final service = CoverSyncService(
    tracksRepository: ref.watch(tracksRepositoryProvider),
    discoveryService: ref.watch(discoveryServiceProvider),
    client: ref.watch(fileTransferClientProvider),
    coverCacheDir: coverDir,
    filePort: fileTransferPort,
  );
  ref.onDispose(service.dispose);
  return service;
});

final pairingServerProvider = Provider<PairingServer>((ref) {
  final server = PairingServer(port: pairingPort);
  ref.onDispose(server.dispose);
  return server;
});

final pairingClientProvider = Provider<PairingClient>((ref) => PairingClient());

/// Turns a discovered-but-unpaired peer into a `devices` row, only after
/// both sides confirm — see docs/adr/0011-mutual-pairing-confirmation.md.
final pairingServiceProvider = Provider<PairingService>((ref) {
  final self = ref.watch(selfDeviceProvider);
  final service = PairingService(
    server: ref.watch(pairingServerProvider),
    client: ref.watch(pairingClientProvider),
    devicesRepository: ref.watch(devicesRepositoryProvider),
    metadataSyncService: ref.watch(metadataSyncServiceProvider),
    selfId: self.id,
    selfName: self.name,
    pairingPort: pairingPort,
    metadataSyncPort: metadataSyncPort,
  );
  ref.onDispose(service.dispose);
  return service;
});
