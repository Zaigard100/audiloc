import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
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

  test('allGenres returns distinct non-empty genres', () async {
    await repository.upsert(track);
    await repository.upsert(const Track(id: 'hash-2', path: '/music/b.mp3', genre: 'Rock'));
    await repository.upsert(const Track(id: 'hash-3', path: '/music/c.mp3', genre: 'Jazz'));
    await repository.upsert(const Track(id: 'hash-4', path: '/music/d.mp3'));

    expect(await repository.allGenres(), unorderedEquals(['Rock', 'Jazz']));
  });
}
