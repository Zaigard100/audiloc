import 'dart:convert';
import 'dart:io';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/services/sync/files/file_transfer_client.dart';
import 'package:audiloc/services/sync/files/file_transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real HTTP round-trip between AudiLoc's own file server and client —
/// the built-in replacement for shelling out to Syncthing, see
/// docs/adr/0010-built-in-file-transfer.md. No mocks: this is the actual
/// server the app runs, hit with the actual client the app uses.
void main() {
  late Directory sourceDir;
  late Directory destDir;
  late AudilocDatabase db;
  late TracksRepository tracksRepository;
  late FileTransferServer server;

  const port = 8561; // distinct from the app's default (8542) and from
  // metadata_sync_roundtrip_test's port, so this file can run alongside
  // either without colliding.

  setUp(() async {
    sourceDir = await Directory.systemTemp.createTemp('audiloc_ft_src_');
    destDir = await Directory.systemTemp.createTemp('audiloc_ft_dst_');
    db = await AudilocDatabase.openInMemory();
    tracksRepository = TracksRepository(db.crdt);
    server = FileTransferServer(tracksRepository: tracksRepository, port: port);
    await server.start();
  });

  tearDown(() async {
    await server.dispose();
    await db.close();
    await sourceDir.delete(recursive: true);
    await destDir.delete(recursive: true);
  });

  Future<File> writeSourceFile(String name, List<int> bytes) async {
    final file = File('${sourceDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('downloads a track from this device\'s own server, bytes and extension intact', () async {
    final bytes = utf8.encode('not really an mp3, just some bytes to move around');
    final sourceFile = await writeSourceFile('song.mp3', bytes);
    await tracksRepository.upsert(Track(id: 'track-1', path: sourceFile.path, title: 'Song'));

    final client = FileTransferClient();
    final downloadedPath = await client.download(
      host: '127.0.0.1',
      port: port,
      trackId: 'track-1',
      destinationDir: destDir,
    );

    expect(downloadedPath, endsWith('.mp3'));
    expect(await File(downloadedPath).readAsBytes(), bytes);
  });

  test('a resumed download (partial file already present) completes with correct bytes', () async {
    final bytes = List<int>.generate(200000, (i) => i % 256); // big enough to meaningfully split
    final sourceFile = await writeSourceFile('big.flac', bytes);
    await tracksRepository.upsert(Track(id: 'track-2', path: sourceFile.path, title: 'Big Song'));

    // Simulate a previous attempt that got half-way through.
    final partial = File('${destDir.path}/track-2.part');
    await partial.writeAsBytes(bytes.sublist(0, 100000));

    final client = FileTransferClient();
    final downloadedPath = await client.download(
      host: '127.0.0.1',
      port: port,
      trackId: 'track-2',
      destinationDir: destDir,
    );

    expect(await File(downloadedPath).readAsBytes(), bytes);
  });

  test('onProgress reports byte counts against the whole file, not just the resumed remainder', () async {
    final bytes = List<int>.generate(200000, (i) => i % 256);
    final sourceFile = await writeSourceFile('big2.flac', bytes);
    await tracksRepository.upsert(Track(id: 'track-3', path: sourceFile.path, title: 'Big Song 2'));

    final partial = File('${destDir.path}/track-3.part');
    await partial.writeAsBytes(bytes.sublist(0, 100000));

    final client = FileTransferClient();
    final updates = <(int, int)>[];
    await client.download(
      host: '127.0.0.1',
      port: port,
      trackId: 'track-3',
      destinationDir: destDir,
      onProgress: (received, total) => updates.add((received, total)),
    );

    expect(updates, isNotEmpty);
    // Every update is against the full 200000-byte file, not the 100000
    // remaining bytes this particular request actually streams.
    expect(updates.every((u) => u.$2 == 200000), isTrue);
    expect(updates.every((u) => u.$1 >= 100000), isTrue);
    expect(updates.last.$1, 200000);
  });

  test('requesting an unknown track fails rather than silently succeeding', () async {
    final client = FileTransferClient();
    await expectLater(
      client.download(host: '127.0.0.1', port: port, trackId: 'nope', destinationDir: destDir),
      throwsA(anything),
    );
  });

  group('cover art (docs/adr/0012-local-cover-paths.md)', () {
    test('downloads a track\'s cover art from this device\'s own server', () async {
      final coverBytes = utf8.encode('not really a jpeg, just some cover bytes');
      final coverFile = await writeSourceFile('cover.jpg', coverBytes);
      final audioFile = await writeSourceFile('song.mp3', utf8.encode('audio bytes'));
      await tracksRepository.upsert(Track(
        id: 'track-cover-1',
        path: audioFile.path,
        coverPath: coverFile.path,
        title: 'Song',
      ));

      final downloadedPath = await FileTransferClient().downloadCover(
        host: '127.0.0.1',
        port: port,
        trackId: 'track-cover-1',
        destinationDir: destDir,
      );

      expect(downloadedPath, endsWith('track-cover-1.cover'));
      expect(await File(downloadedPath).readAsBytes(), coverBytes);
    });

    test('requesting a cover for a track that has none fails rather than silently succeeding', () async {
      final audioFile = await writeSourceFile('song2.mp3', utf8.encode('audio bytes'));
      await tracksRepository.upsert(Track(id: 'track-no-cover', path: audioFile.path, title: 'Song'));

      await expectLater(
        FileTransferClient().downloadCover(
          host: '127.0.0.1',
          port: port,
          trackId: 'track-no-cover',
          destinationDir: destDir,
        ),
        throwsA(anything),
      );
    });
  });
}
