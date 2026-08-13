import 'dart:io';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:crdt/crdt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudilocDatabase db;
  late TracksRepository repository;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    repository = TracksRepository(db.crdt);
  });

  tearDown(() => db.close());

  const track = Track(
    id: 'hash-1',
    path: '/music/song.mp3',
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    genre: 'Rock',
    durationMs: 200000,
  );

  test('upsert then byId round-trips all fields', () async {
    await repository.upsert(track);
    final fetched = await repository.byId(track.id);

    expect(fetched, isNotNull);
    expect(fetched!.title, 'Song');
    expect(fetched.artist, 'Artist');
    expect(fetched.album, 'Album');
    expect(fetched.genre, 'Rock');
    expect(fetched.durationMs, 200000);
  });

  test('byId returns null for unknown id', () async {
    expect(await repository.byId('missing'), isNull);
  });

  test('exists reflects presence', () async {
    expect(await repository.exists(track.id), isFalse);
    await repository.upsert(track);
    expect(await repository.exists(track.id), isTrue);
  });

  test('delete soft-deletes: excluded from reads without losing history', () async {
    await repository.upsert(track);
    await repository.delete(track.id);

    expect(await repository.exists(track.id), isFalse);
    expect(await repository.byId(track.id), isNull);
    expect(await repository.all(), isEmpty);
  });

  test('delete leaves the track visible in watchDeleted, restore brings it back', () async {
    await repository.upsert(track);
    await repository.delete(track.id);

    final deleted = await repository.watchDeleted().first;
    expect(deleted.single.id, track.id);
    expect(deleted.single.path, track.path, reason: 'the file itself was never touched');

    await repository.restore(track.id);

    expect(await repository.exists(track.id), isTrue);
    expect(await repository.watchDeleted().first, isEmpty);
    expect((await repository.byId(track.id))!.title, track.title);
  });

  test('upsert revives a previously soft-deleted track with the same id', () async {
    await repository.upsert(track);
    await repository.delete(track.id);

    final revived = track.copyWith(title: 'Song (re-imported)');
    await repository.upsert(revived);

    final fetched = await repository.byId(track.id);
    expect(fetched, isNotNull);
    expect(fetched!.title, 'Song (re-imported)');
  });

  test('upsert with same id updates fields instead of duplicating', () async {
    await repository.upsert(track);
    await repository.upsert(track.copyWith(genre: 'Jazz'));

    final all = await repository.all();
    expect(all, hasLength(1));
    expect(all.single.genre, 'Jazz');
  });

  test('watchAll emits a new list when a track is inserted', () async {
    final emission = repository.watchAll().firstWhere((tracks) => tracks.isNotEmpty);
    await repository.upsert(track);

    final tracks = await emission;
    expect(tracks.single.id, track.id);
  });

  test(
      'importing the same content on two devices keeps each device on its own local path '
      'after merging the other device\'s sync (regression: path used to be clobbered '
      'row-wide by whichever import had the later HLC, causing playback to open a path '
      'that only existed on the other device)', () async {
    final peerDb = await AudilocDatabase.openInMemory();
    addTearDown(peerDb.close);
    final peerRepository = TracksRepository(peerDb.crdt);

    const sharedId = 'same-content-hash';
    await repository.upsert(const Track(id: sharedId, path: '/android/song.mp3', title: 'Song'));
    // A later write, simulating the peer importing the identical file
    // (same content hash) at its own, different local path.
    await peerRepository.upsert(const Track(id: sharedId, path: '/linux/song.mp3', title: 'Song'));

    // Merge the peer's changeset in, as metadata sync would. getChangeset()
    // returns raw DB rows with `hlc` as text; over the wire crdt_sync
    // parses that back into an Hlc before merge() sees it, so do the same
    // here rather than going through a real socket.
    final rawChangeset = await peerDb.crdt.getChangeset();
    final changeset = {
      for (final entry in rawChangeset.entries)
        entry.key: [
          for (final record in entry.value) {...record, 'hlc': (record['hlc']! as String).toHlc},
        ],
    };
    await db.crdt.merge(changeset);

    final merged = await repository.byId(sharedId);
    expect(merged, isNotNull);
    expect(merged!.path, '/android/song.mp3', reason: 'must keep this device\'s own path, not the peer\'s');
  });

  test('a track known only through sync (no local file) has a null path and shows up as missing', () async {
    final peerDb = await AudilocDatabase.openInMemory();
    addTearDown(peerDb.close);
    final peerRepository = TracksRepository(peerDb.crdt);

    await peerRepository.upsert(const Track(id: 'peer-only', path: '/linux/song.mp3', title: 'Song'));

    final rawChangeset = await peerDb.crdt.getChangeset();
    final changeset = {
      for (final entry in rawChangeset.entries)
        entry.key: [
          for (final record in entry.value) {...record, 'hlc': (record['hlc']! as String).toHlc},
        ],
    };
    await db.crdt.merge(changeset);

    final track = await repository.byId('peer-only');
    expect(track, isNotNull);
    expect(track!.path, isNull);
    expect(track.isAvailableLocally, isFalse);

    final missing = await repository.watchMissingFiles().first;
    expect(missing.map((t) => t.id), contains('peer-only'));

    final peers = await repository.peersWithLocalCopy('peer-only');
    expect(peers, [peerDb.nodeId]);
  });

  test('peersWithLocalCopy excludes this device even though it has the file', () async {
    await repository.upsert(track);
    expect(await repository.peersWithLocalCopy(track.id), isEmpty);
  });

  test(
      'backfillLocalFileLocations recovers a track imported before track_locations '
      'existed (regression: after tl.path stopped falling back to tracks.path, such '
      'tracks looked permanently "missing" despite the file still being right there)',
      () async {
    final dir = await Directory.systemTemp.createTemp('audiloc_backfill_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/song.mp3')..writeAsBytesSync([1, 2, 3]);

    // Simulate a pre-migration row: tracks.path set, but no track_locations
    // row for this device (as if imported before upsert() wrote one).
    await db.crdt.execute('''
      INSERT INTO tracks (id, path, title) VALUES (?1, ?2, ?3)
    ''', ['legacy-track', file.path, 'Legacy Song']);

    expect((await repository.byId('legacy-track'))!.path, isNull, reason: 'not backfilled yet');
    expect((await repository.watchMissingFiles().first).map((t) => t.id), contains('legacy-track'));

    await repository.backfillLocalFileLocations();

    final recovered = await repository.byId('legacy-track');
    expect(recovered!.path, file.path);
    expect((await repository.watchMissingFiles().first).map((t) => t.id), isNot(contains('legacy-track')));
  });

  test('backfillLocalFileLocations does not adopt a path whose file does not actually exist here', () async {
    // A track known only through sync: tracks.path holds a peer's path,
    // which must never be trusted as this device's own local file.
    await db.crdt.execute('''
      INSERT INTO tracks (id, path, title) VALUES (?1, ?2, ?3)
    ''', ['peer-track', '/some/other/device/song.mp3', 'Peer Song']);

    await repository.backfillLocalFileLocations();

    expect((await repository.byId('peer-track'))!.path, isNull);
  });

  group('cover art (docs/adr/0012-local-cover-paths.md)', () {
    Future<void> mergeFrom(AudilocDatabase peerDb) async {
      final rawChangeset = await peerDb.crdt.getChangeset();
      final changeset = {
        for (final entry in rawChangeset.entries)
          entry.key: [
            for (final record in entry.value) {...record, 'hlc': (record['hlc']! as String).toHlc},
          ],
      };
      await db.crdt.merge(changeset);
    }

    test(
        'cover art known only through sync has a null coverPath and is not yet a '
        '"missing cover" until the audio file itself is local', () async {
      final peerDb = await AudilocDatabase.openInMemory();
      addTearDown(peerDb.close);
      final peerRepository = TracksRepository(peerDb.crdt);

      await peerRepository.upsert(const Track(
        id: 'peer-only',
        path: '/linux/song.mp3',
        coverPath: '/linux/covers/peer-only.cover',
        title: 'Song',
      ));
      await mergeFrom(peerDb);

      final track = await repository.byId('peer-only');
      expect(track!.coverPath, isNull, reason: 'the peer\'s absolute cover path is never trustworthy here');

      // Audio isn't local yet either, so there's no point fetching cover
      // art for it yet.
      expect((await repository.watchMissingCovers().first).map((t) => t.id), isNot(contains('peer-only')));

      // Once the audio file becomes local (simulating FileSyncService
      // finishing a download), the cover becomes a real candidate.
      await repository.recordLocalFile('peer-only', '/this-device/song.mp3');
      expect((await repository.watchMissingCovers().first).map((t) => t.id), contains('peer-only'));

      final peers = await repository.peersWithLocalCover('peer-only');
      expect(peers, [peerDb.nodeId]);
    });

    test('recordLocalCover makes the cover resolve locally and drops it from watchMissingCovers', () async {
      final peerDb = await AudilocDatabase.openInMemory();
      addTearDown(peerDb.close);
      final peerRepository = TracksRepository(peerDb.crdt);

      await peerRepository.upsert(const Track(
        id: 'shared',
        path: '/linux/song.mp3',
        coverPath: '/linux/covers/shared.cover',
        title: 'Song',
      ));
      await mergeFrom(peerDb);
      await repository.recordLocalFile('shared', '/this-device/song.mp3');

      await repository.recordLocalCover('shared', '/this-device/covers/shared.cover');

      final track = await repository.byId('shared');
      expect(track!.coverPath, '/this-device/covers/shared.cover');
      expect((await repository.watchMissingCovers().first).map((t) => t.id), isNot(contains('shared')));
    });

    test(
        'backfillLocalCovers recovers a cover this device already cached before '
        'track_locations.cover_path existed, but only if the file is actually there',
        () async {
      final dir = await Directory.systemTemp.createTemp('audiloc_cover_backfill_');
      addTearDown(() => dir.delete(recursive: true));
      final coverFile = File('${dir.path}/legacy-track.cover')..writeAsBytesSync([1, 2, 3]);

      // Simulate a track this device already has the audio for (a real
      // track_locations row), with a stale/foreign tracks.cover_path (as
      // if synced from whichever device originally extracted it) and no
      // cover_path of its own yet.
      await repository.upsert(const Track(id: 'legacy-track', path: '/music/song.mp3', title: 'Song'));
      await db.crdt.execute(
        "UPDATE tracks SET cover_path = '/some/other/device/covers/legacy-track.cover' WHERE id = 'legacy-track'",
      );

      expect((await repository.byId('legacy-track'))!.coverPath, isNull, reason: 'not backfilled yet');

      await repository.backfillLocalCovers(dir);

      expect((await repository.byId('legacy-track'))!.coverPath, coverFile.path);
    });

    test('backfillLocalCovers does nothing when no local cover file actually exists', () async {
      final dir = await Directory.systemTemp.createTemp('audiloc_cover_backfill_empty_');
      addTearDown(() => dir.delete(recursive: true));

      await repository.upsert(const Track(id: 'legacy-track', path: '/music/song.mp3', title: 'Song'));
      await db.crdt.execute(
        "UPDATE tracks SET cover_path = '/some/other/device/covers/legacy-track.cover' WHERE id = 'legacy-track'",
      );

      await repository.backfillLocalCovers(dir);

      expect((await repository.byId('legacy-track'))!.coverPath, isNull);
    });
  });

  group('eraseFileFromDisk ("Стереть навсегда", docs/adr/0014, docs/adr/0023)', () {
    test(
        'deletes the local audio and cover files, and the track disappears from watchDeleted '
        'entirely — "Стереть навсегда" must not linger looking like a re-downloadable track',
        () async {
      final dir = await Directory.systemTemp.createTemp('audiloc_erase_');
      addTearDown(() => dir.delete(recursive: true));
      final audioFile = File('${dir.path}/song.mp3')..writeAsBytesSync([1, 2, 3]);
      final coverFile = File('${dir.path}/song.cover')..writeAsBytesSync([4, 5, 6]);

      await repository.upsert(
        Track(id: 'erase-me', path: audioFile.path, coverPath: coverFile.path, title: 'Song'),
      );
      await repository.delete('erase-me'); // "Стереть навсегда" is only reachable from Удалённые
      expect(await repository.watchDeleted().first, isNotEmpty, reason: 'sanity check before erasing');

      await repository.eraseFileFromDisk('erase-me');

      expect(await audioFile.exists(), isFalse);
      expect(await coverFile.exists(), isFalse);
      expect(
        (await repository.watchDeleted().first).where((t) => t.id == 'erase-me'),
        isEmpty,
        reason: 'erased forever — gone from Удалённые, not just fileless',
      );
    });

    test('is a no-op when this device never had a local copy to begin with', () async {
      // Nothing to erase — must not throw.
      await repository.eraseFileFromDisk('never-had-it');
    });

    test('does not error when the file was already missing from disk (e.g. deleted by hand)', () async {
      final dir = await Directory.systemTemp.createTemp('audiloc_erase_missing_');
      addTearDown(() => dir.delete(recursive: true));
      final audioFile = File('${dir.path}/song.mp3')..writeAsBytesSync([1, 2, 3]);

      await repository.upsert(Track(id: 'erase-me', path: audioFile.path, title: 'Song'));
      await repository.delete('erase-me');
      await audioFile.delete(); // simulate the file already being gone

      await repository.eraseFileFromDisk('erase-me'); // must not throw

      expect((await repository.watchDeleted().first).where((t) => t.id == 'erase-me'), isEmpty);
    });

    test(
        'a track soft-deleted normally (never erased) still shows up in watchDeleted, file intact',
        () async {
      final dir = await Directory.systemTemp.createTemp('audiloc_erase_untouched_');
      addTearDown(() => dir.delete(recursive: true));
      final audioFile = File('${dir.path}/song.mp3')..writeAsBytesSync([1, 2, 3]);

      await repository.upsert(Track(id: 'just-deleted', path: audioFile.path, title: 'Song'));
      await repository.delete('just-deleted');

      final deleted = (await repository.watchDeleted().first).singleWhere((t) => t.id == 'just-deleted');
      expect(deleted.path, audioFile.path);
      expect(await audioFile.exists(), isTrue);
    });

    test(
        'a track known only via sync, never downloaded to this device, still shows up in '
        'watchDeleted — distinct from an erased one (no track_locations row for this node at all, '
        'ever, vs. one that exists but is soft-deleted)', () async {
      // Simulates metadata (not the file) arriving via CRDT sync from a
      // peer — a bare tracks row, written directly rather than through
      // TracksRepository.upsert() (which always records a local
      // track_locations row, since it means "this device has the file").
      await db.crdt.execute(
        "INSERT INTO tracks (id, path, title) VALUES ('remote-only', '/peer/song.mp3', 'Remote Song')",
        const [],
      );
      await repository.delete('remote-only');

      final deleted = await repository.watchDeleted().first;
      expect(deleted.map((t) => t.id), contains('remote-only'));
    });
  });
}
