import 'dart:io';

import 'package:audiloc/data/profiles/profiles_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory appSupportDir;
  late ProfilesStore store;

  setUp(() async {
    appSupportDir = await Directory.systemTemp.createTemp('audiloc_profiles_');
    store = ProfilesStore(appSupportDir);
  });

  tearDown(() => appSupportDir.delete(recursive: true));

  test('create then list round-trips, and creates the profile\'s own directory', () async {
    final profile = await store.create('Мама');

    final all = await store.list();
    expect(all, hasLength(1));
    expect(all.single.id, profile.id);
    expect(all.single.name, 'Мама');
    expect(await store.profileDir(profile.id).exists(), isTrue);
  });

  test('rename updates the name without touching id/createdAt', () async {
    final profile = await store.create('Мама');
    await store.rename(profile.id, 'Мамуля');

    final renamed = (await store.list()).single;
    expect(renamed.id, profile.id);
    expect(renamed.name, 'Мамуля');
    expect(renamed.createdAt, profile.createdAt);
  });

  test('setActiveProfileId/activeProfileId round-trips', () async {
    final a = await store.create('A');
    await store.create('B');
    await store.setActiveProfileId(a.id);

    expect(await store.activeProfileId(), a.id);
  });

  test('create does not clobber an already-set activeProfileId (regression: '
      'copyWith used to reset it to null on every create/rename call)', () async {
    final a = await store.create('A');
    await store.setActiveProfileId(a.id);

    await store.create('B');

    expect(await store.activeProfileId(), a.id);
  });

  test('delete only unregisters the profile — its directory is left on disk', () async {
    final profile = await store.create('Мама');
    await store.delete(profile.id);

    expect(await store.list(), isEmpty);
    expect(await store.profileDir(profile.id).exists(), isTrue, reason: 'non-destructive by design');
  });

  test('delete clears activeProfileId if it pointed at the deleted profile', () async {
    final profile = await store.create('Мама');
    await store.setActiveProfileId(profile.id);

    await store.delete(profile.id);

    expect(await store.activeProfileId(), isNull);
  });

  group('resolveActiveProfileId', () {
    test('returns the existing active profile unchanged', () async {
      final a = await store.create('A');
      await store.create('B');
      await store.setActiveProfileId(a.id);

      expect(await store.resolveActiveProfileId(), a.id);
    });

    test('falls back to any remaining profile if the active one was deleted', () async {
      final a = await store.create('A');
      await store.setActiveProfileId(a.id);
      await store.delete(a.id);
      final b = await store.create('B');

      final resolved = await store.resolveActiveProfileId();
      expect(resolved, b.id);
      expect(await store.activeProfileId(), b.id, reason: 'should persist the fallback choice');
    });

    test('a fresh install (no registry, no legacy db) silently creates one default profile', () async {
      final id = await store.resolveActiveProfileId();

      final all = await store.list();
      expect(all, hasLength(1));
      expect(all.single.id, id);
      expect(await store.activeProfileId(), id);
    });

    test(
        'migrates a pre-accounts flat audiloc.db (plus covers/ and synced_music/) into the new '
        'profile\'s own directory, preserving content, so upgrading never loses a library', () async {
      final legacyDb = File(p.join(appSupportDir.path, 'audiloc.db'));
      await legacyDb.writeAsBytes([1, 2, 3, 4]);
      final coversDir = Directory(p.join(appSupportDir.path, 'covers'))..createSync();
      await File(p.join(coversDir.path, 'track-1.cover')).writeAsBytes([9, 9]);
      final syncedMusicDir = Directory(p.join(appSupportDir.path, 'synced_music'))..createSync();
      await File(p.join(syncedMusicDir.path, 'track-2.mp3')).writeAsBytes([7, 7]);

      final id = await store.resolveActiveProfileId();

      expect(await legacyDb.exists(), isFalse, reason: 'moved, not copied');
      final movedDb = File(p.join(store.profileDir(id).path, 'audiloc.db'));
      expect(await movedDb.readAsBytes(), [1, 2, 3, 4]);
      final movedCover = File(p.join(store.profileDir(id).path, 'covers', 'track-1.cover'));
      expect(await movedCover.readAsBytes(), [9, 9]);
      final movedTrack = File(p.join(store.profileDir(id).path, 'synced_music', 'track-2.mp3'));
      expect(await movedTrack.readAsBytes(), [7, 7]);
      expect(await store.activeProfileId(), id);
    });

    test('does not migrate anything when there is no legacy audiloc.db', () async {
      final id = await store.resolveActiveProfileId();

      expect(await File(p.join(store.profileDir(id).path, 'audiloc.db')).exists(), isFalse);
    });
  });
}
