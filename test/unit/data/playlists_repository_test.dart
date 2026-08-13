import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/playlists_repository.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudilocDatabase db;
  late PlaylistsRepository playlists;
  late TracksRepository tracks;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    playlists = PlaylistsRepository(db.crdt);
    tracks = TracksRepository(db.crdt);

    for (final id in ['t1', 't2', 't3']) {
      await tracks.upsert(Track(id: id, path: '/music/$id.mp3', title: id));
    }
  });

  tearDown(() => db.close());

  test('create then watchPlaylists includes it', () async {
    final created = await playlists.create('Roadtrip');
    final list = await playlists.watchPlaylists().first;
    expect(list.map((p) => p.id), contains(created.id));
    expect(list.single.name, 'Roadtrip');
  });

  test('addTrack appends in insertion order', () async {
    final playlist = await playlists.create('Roadtrip');
    await playlists.addTrack(playlist.id, 't1');
    await playlists.addTrack(playlist.id, 't2');
    await playlists.addTrack(playlist.id, 't3');

    final ordered = await playlists.watchTracks(playlist.id).first;
    expect(ordered.map((t) => t.id).toList(), ['t1', 't2', 't3']);
  });

  test('moveEntry between two neighbours reorders without touching them', () async {
    final playlist = await playlists.create('Roadtrip');
    await playlists.addTrack(playlist.id, 't1');
    await playlists.addTrack(playlist.id, 't2');
    await playlists.addTrack(playlist.id, 't3');

    final entries = await playlists.watchEntries(playlist.id).first;
    final t1Entry = entries.firstWhere((e) => e.trackId == 't1');
    final t2Entry = entries.firstWhere((e) => e.trackId == 't2');
    final t3Entry = entries.firstWhere((e) => e.trackId == 't3');

    // Move t3 between t1 and t2 -> t1, t3, t2
    await playlists.moveEntry(t3Entry.id, beforePosition: t1Entry.position, afterPosition: t2Entry.position);

    final ordered = await playlists.watchTracks(playlist.id).first;
    expect(ordered.map((t) => t.id).toList(), ['t1', 't3', 't2']);
  });

  test('removeEntry drops the track from the playlist but not from the library', () async {
    final playlist = await playlists.create('Roadtrip');
    await playlists.addTrack(playlist.id, 't1');
    final entry = (await playlists.watchEntries(playlist.id).first).single;

    await playlists.removeEntry(entry.id);

    expect(await playlists.watchTracks(playlist.id).first, isEmpty);
    expect(await tracks.exists('t1'), isTrue);
  });

  test('watchItems exposes the entry id and position alongside the joined track', () async {
    final playlist = await playlists.create('Roadtrip');
    await playlists.addTrack(playlist.id, 't1');

    final items = await playlists.watchItems(playlist.id).first;
    expect(items.single.track.id, 't1');
    expect(items.single.entryId, isNotEmpty);
    expect(items.single.position, isPositive);
  });

  test(
      'moveEntry reorders using watchItems\' own position values — the drag-and-drop '
      'path in PlaylistDetailScreen', () async {
    final playlist = await playlists.create('Roadtrip');
    await playlists.addTrack(playlist.id, 't1');
    await playlists.addTrack(playlist.id, 't2');
    await playlists.addTrack(playlist.id, 't3');

    final items = await playlists.watchItems(playlist.id).first;
    expect(items.map((i) => i.track.id), ['t1', 't2', 't3']);

    // Drag t1 to the end: its new neighbours are t3 (before) and nothing
    // (after) — exactly what PlaylistDetailScreen._reorder computes from
    // the post-move list.
    await playlists.moveEntry(items[0].entryId, beforePosition: items[2].position, afterPosition: null);

    final reordered = await playlists.watchItems(playlist.id).first;
    expect(reordered.map((i) => i.track.id), ['t2', 't3', 't1']);
  });

  test('delete removes the playlist and its entries', () async {
    final playlist = await playlists.create('Roadtrip');
    await playlists.addTrack(playlist.id, 't1');

    await playlists.delete(playlist.id);

    expect(await playlists.watchPlaylists().first, isEmpty);
    expect(await playlists.watchTracks(playlist.id).first, isEmpty);
  });

  test('rename updates the name without touching id or its tracks', () async {
    final playlist = await playlists.create('Roadtrip');
    await playlists.addTrack(playlist.id, 't1');

    await playlists.rename(playlist.id, 'Summer Roadtrip');

    final renamed = (await playlists.watchPlaylists().first).single;
    expect(renamed.id, playlist.id);
    expect(renamed.name, 'Summer Roadtrip');
    expect(await playlists.watchTracks(playlist.id).first, hasLength(1));
  });

  group(
      'cover (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md — '
      'a playlist\'s cover is either one of its own tracks\' art, or a picked file, never both)',
      () {
    setUp(() async {
      // t1 gets real cover art recorded for *this* device — the same
      // shape TracksRepository.upsert leaves in track_locations.
      await tracks.upsert(Track(id: 't1', path: '/music/t1.mp3', title: 't1', coverPath: '/covers/t1.cover'));
    });

    test('setCoverFromTrack resolves coverPath through that track\'s own local cover', () async {
      final playlist = await playlists.create('Roadtrip');

      await playlists.setCoverFromTrack(playlist.id, 't1');

      final updated = (await playlists.watchPlaylists().first).single;
      expect(updated.coverTrackId, 't1');
      expect(updated.coverPath, '/covers/t1.cover');
    });

    test('setCoverFromFile sets a custom cover and clears any track-based one', () async {
      final playlist = await playlists.create('Roadtrip');
      await playlists.setCoverFromTrack(playlist.id, 't1');

      await playlists.setCoverFromFile(playlist.id, '/covers/playlist-custom.cover');

      final updated = (await playlists.watchPlaylists().first).single;
      expect(updated.coverTrackId, isNull);
      expect(updated.coverPath, '/covers/playlist-custom.cover');
    });

    test('setCoverFromTrack overrides a previously set custom file cover', () async {
      final playlist = await playlists.create('Roadtrip');
      await playlists.setCoverFromFile(playlist.id, '/covers/playlist-custom.cover');

      await playlists.setCoverFromTrack(playlist.id, 't1');

      final updated = (await playlists.watchPlaylists().first).single;
      expect(updated.coverTrackId, 't1');
      expect(updated.coverPath, '/covers/t1.cover');
    });

    test('a playlist with no cover set resolves coverPath to null', () async {
      final playlist = await playlists.create('Roadtrip');

      final fetched = (await playlists.watchPlaylists().first).single;
      expect(fetched.id, playlist.id);
      expect(fetched.coverTrackId, isNull);
      expect(fetched.coverPath, isNull);
    });
  });
}
