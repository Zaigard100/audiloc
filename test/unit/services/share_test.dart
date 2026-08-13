import 'dart:io';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/services/dedupe/dedupe_service.dart';
import 'package:audiloc/services/library_import/library_import_service.dart';
import 'package:audiloc/services/library_import/tag_reader.dart';
import 'package:audiloc/services/sync/files/file_transfer_client.dart';
import 'package:audiloc/services/sync/files/file_transfer_server.dart';
import 'package:audiloc/services/sync/share/share_client.dart';
import 'package:audiloc/services/sync/share/share_models.dart';
import 'package:audiloc/services/sync/share/share_server.dart';
import 'package:audiloc/services/sync/share/share_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `audiotags` is a native FFI plugin, not loadable under plain
/// `flutter test` — same workaround as `library_import_service_test.dart`.
class _FakeTagReader extends TagReader {
  _FakeTagReader(this._tags);
  final Map<String, TrackTags?> _tags;
  @override
  Future<TrackTags?> read(String path) async => _tags[path];
}

/// Real (non-mocked) HTTP round-trips for "Поделиться" — see
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md. Unlike
/// pairing, this protocol works between any two devices regardless of
/// profile or pairing status, so `acceptOffer` is exercised against a
/// real `FileTransferServer` + `LibraryImportService`, not a stub.
void main() {
  group('ShareServer/ShareClient protocol', () {
    late ShareServer server;
    const port = 8572;

    setUp(() async {
      server = ShareServer(port: port);
      await server.start();
    });

    tearDown(() => server.dispose());

    test("an offer lands on the server with the sender's id/name and item previews", () async {
      final received = server.offers.first.timeout(const Duration(seconds: 5));

      await ShareClient().sendOffer(
        host: '127.0.0.1',
        port: port,
        fromId: 'peer-1',
        fromName: 'Peer',
        items: const [ShareItemPreview(trackId: 't1', title: 'Song', artist: 'Artist', album: 'Album')],
      );

      final offer = await received;
      expect(offer.fromId, 'peer-1');
      expect(offer.fromName, 'Peer');
      expect(offer.items, hasLength(1));
      expect(offer.items.single.trackId, 't1');
      expect(offer.items.single.title, 'Song');
      expect(offer.items.single.artist, 'Artist');
      expect(offer.items.single.album, 'Album');
    });

    test('a response carries accepted through', () async {
      final received = server.responses.first.timeout(const Duration(seconds: 5));

      await ShareClient().sendResponse(host: '127.0.0.1', port: port, fromId: 'peer-1', fromName: 'Peer', accepted: true);

      expect((await received).accepted, isTrue);
    });
  });

  group('ShareService', () {
    late Directory tempDir;
    late AudilocDatabase senderDb;
    late AudilocDatabase receiverDb;
    late TracksRepository senderTracks;
    late TracksRepository receiverTracks;
    late FileTransferServer fileTransferServer;
    late ShareServer shareServer;
    late ShareService shareService;

    const sharePort = 8573;
    const fileTransferPort = 8574;
    const senderAudioBytes = [1, 2, 3, 4, 5];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audiloc_share_test_');
      senderDb = await AudilocDatabase.openInMemory();
      receiverDb = await AudilocDatabase.openInMemory();
      senderTracks = TracksRepository(senderDb.crdt);
      receiverTracks = TracksRepository(receiverDb.crdt);

      // Sender side: a track already in its own library, served over the
      // same plain-HTTP file transfer every other sync path already uses
      // (lib/services/sync/files/file_transfer_server.dart) — no auth
      // gate there, so this works without any pairing at all.
      final audioFile = File('${tempDir.path}/song.mp3')..writeAsBytesSync(senderAudioBytes);
      await senderTracks.upsert(Track(
        id: 'song-hash',
        path: audioFile.path,
        title: 'Shared Song',
        artist: 'Artist',
        album: 'Album',
      ));
      fileTransferServer = FileTransferServer(tracksRepository: senderTracks, port: fileTransferPort);
      await fileTransferServer.start();

      // Receiver side: real ShareServer + ShareService wired to a real
      // LibraryImportService (fake tag reader only, same reason as
      // library_import_service_test.dart) writing into its own dirs.
      shareServer = ShareServer(port: sharePort);
      await shareServer.start();
      final receiverAudioDir = await Directory('${tempDir.path}/receiver_audio').create();
      final receiverCoverDir = await Directory('${tempDir.path}/receiver_covers').create();
      final importService = LibraryImportService(
        tracksRepository: receiverTracks,
        tagReader: _FakeTagReader(const {}),
        dedupeService: DedupeService(),
        deviceId: 'receiver-device',
        coverCacheDir: receiverCoverDir,
        audioStorageDir: receiverAudioDir,
      );
      shareService = ShareService(
        server: shareServer,
        client: ShareClient(),
        fileTransferClient: FileTransferClient(),
        resolveImportService: () async => importService,
        selfId: 'receiver-device',
        selfName: 'Receiver',
        sharePort: sharePort,
        fileTransferPort: fileTransferPort,
      );
    });

    tearDown(() async {
      await fileTransferServer.dispose();
      await shareServer.dispose();
      await senderDb.close();
      await receiverDb.close();
      await tempDir.delete(recursive: true);
    });

    test(
        'acceptOffer downloads the file from the sender and imports it into the local library, '
        'without touching devices/pairing at all', () async {
      const offer = IncomingShareOffer(
        fromId: 'sender-device',
        fromName: 'Sender',
        fromHost: '127.0.0.1',
        items: [ShareItemPreview(trackId: 'song-hash', title: 'Shared Song', artist: 'Artist', album: 'Album')],
      );

      await shareService.acceptOffer(offer);

      final imported = await receiverTracks.all();
      expect(imported, hasLength(1));
      expect(await File(imported.single.path!).readAsBytes(), senderAudioBytes);
    });

    test('acceptOffer sends an accepted response back to the offerer before downloading', () async {
      final received = shareServer.responses.first.timeout(const Duration(seconds: 5));
      const offer = IncomingShareOffer(
        fromId: 'sender-device',
        fromName: 'Sender',
        // Self-loop, same trick as pairing_test.dart: fromHost points
        // back at our own shareServer, so its `responses` stream is what
        // observes the reply.
        fromHost: '127.0.0.1',
        items: [ShareItemPreview(trackId: 'song-hash', title: 'Shared Song', artist: null, album: null)],
      );

      await shareService.acceptOffer(offer);

      expect((await received).accepted, isTrue);
    });

    test('rejectOffer answers with accepted: false and imports nothing', () async {
      final received = shareServer.responses.first.timeout(const Duration(seconds: 5));
      const offer = IncomingShareOffer(
        fromId: 'sender-device',
        fromName: 'Sender',
        fromHost: '127.0.0.1',
        items: [ShareItemPreview(trackId: 'song-hash', title: 'Shared Song', artist: null, album: null)],
      );

      await shareService.rejectOffer(offer);

      expect((await received).accepted, isFalse);
      expect(await receiverTracks.all(), isEmpty);
    });

    test('shareTrack/shareAlbum send an offer built from local Track previews', () async {
      final received = shareServer.offers.first.timeout(const Duration(seconds: 5));

      await shareService.shareTrack(
        host: '127.0.0.1',
        port: sharePort,
        track: const Track(id: 'x', path: '/a.mp3', title: 'X', artist: 'Y', album: 'Z'),
      );

      final offer = await received;
      expect(offer.items.single.trackId, 'x');
      expect(offer.items.single.title, 'X');
      expect(offer.items.single.artist, 'Y');
      expect(offer.items.single.album, 'Z');
    });
  });
}
