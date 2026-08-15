import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/playback_state.dart';
import 'package:audiloc/data/repositories/playback_state_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudilocDatabase db;
  late PlaybackStateRepository repository;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    repository = PlaybackStateRepository(db.crdt);
  });

  tearDown(() => db.close());

  const state = PlaybackState(
    trackId: 'track-1',
    positionMs: 42000,
    queueType: PlaybackQueueType.library,
    deviceId: 'device-a',
    deviceName: 'Ноутбук',
  );

  test('nothing saved yet reads back as null', () async {
    expect(await repository.get(), isNull);
  });

  test('save then get round-trips every field', () async {
    await repository.save(state);
    final result = await repository.get();
    expect(result, isNotNull);
    expect(result!.trackId, 'track-1');
    expect(result.positionMs, 42000);
    expect(result.queueType, PlaybackQueueType.library);
    expect(result.playlistId, isNull);
    expect(result.deviceId, 'device-a');
    expect(result.deviceName, 'Ноутбук');
  });

  test('playlist queue type carries a playlistId through', () async {
    const withPlaylist = PlaybackState(
      trackId: 'track-2',
      positionMs: 1000,
      queueType: PlaybackQueueType.playlist,
      playlistId: 'playlist-1',
      deviceId: 'device-a',
      deviceName: 'Ноутбук',
    );
    await repository.save(withPlaylist);
    expect((await repository.get())!.playlistId, 'playlist-1');
  });

  test('a second save overwrites the first — only ever one row (id = "current")', () async {
    await repository.save(state);
    await repository.save(const PlaybackState(
      trackId: 'track-2',
      positionMs: 5000,
      queueType: PlaybackQueueType.favorites,
      deviceId: 'device-b',
      deviceName: 'Телефон',
    ));

    final result = await repository.get();
    expect(result!.trackId, 'track-2');
    expect(result.deviceId, 'device-b');

    final rows = await db.crdt.query('SELECT * FROM playback_state');
    expect(rows, hasLength(1));
  });

  test('watch() emits the current state and again after a write', () async {
    final stream = repository.watch();
    final emissions = <PlaybackState?>[];
    final sub = stream.listen(emissions.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions, [null]);

    await repository.save(state);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.last?.trackId, 'track-1');
  });
}
