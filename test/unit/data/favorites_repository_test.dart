import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/repositories/favorites_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudilocDatabase db;
  late FavoritesRepository repository;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    repository = FavoritesRepository(db.crdt);
  });

  tearDown(() => db.close());

  test('a track starts out not favorite', () async {
    expect(await repository.isFavorite('track-1'), isFalse);
  });

  test('setFavorite(true) then isFavorite reflects it', () async {
    await repository.setFavorite('track-1', true);
    expect(await repository.isFavorite('track-1'), isTrue);
  });

  test('toggle flips current state', () async {
    await repository.toggle('track-1');
    expect(await repository.isFavorite('track-1'), isTrue);
    await repository.toggle('track-1');
    expect(await repository.isFavorite('track-1'), isFalse);
  });

  test('watchFavoriteIds only includes tracks currently favorited', () async {
    await repository.setFavorite('track-1', true);
    await repository.setFavorite('track-2', true);
    await repository.setFavorite('track-2', false);

    final emission = await repository.watchFavoriteIds().first;
    expect(emission, {'track-1'});
  });
}
