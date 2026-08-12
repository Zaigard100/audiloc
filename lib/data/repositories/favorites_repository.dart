import 'package:sqlite_crdt/sqlite_crdt.dart';

/// CRUD over the `favorites` CRDT table.
///
/// Deliberately a separate table from `tracks` (as specified in ТЗ п.5):
/// favoriting is a tiny, frequently-toggled field, and keeping it apart
/// means a favorite flip on one device never competes on HLC with a tag
/// edit on another for the same row.
class FavoritesRepository {
  FavoritesRepository(this._crdt);

  final SqliteCrdt _crdt;

  Stream<Set<String>> watchFavoriteIds() => _crdt
      .watch('SELECT track_id FROM favorites WHERE is_deleted = 0 AND is_favorite = 1')
      .map((rows) => rows.map((r) => r['track_id']! as String).toSet());

  Future<bool> isFavorite(String trackId) async {
    final rows = await _crdt.query('''
      SELECT is_favorite FROM favorites
      WHERE track_id = ?1 AND is_deleted = 0
    ''', [trackId]);
    if (rows.isEmpty) return false;
    return (rows.first['is_favorite']! as int) == 1;
  }

  Future<void> setFavorite(String trackId, bool isFavorite) => _crdt.execute('''
        INSERT INTO favorites (track_id, is_favorite)
          VALUES (?1, ?2)
        ON CONFLICT (track_id) DO UPDATE SET
          is_favorite = excluded.is_favorite,
          is_deleted = 0
      ''', [trackId, isFavorite ? 1 : 0]);

  Future<void> toggle(String trackId) async {
    final current = await isFavorite(trackId);
    await setFavorite(trackId, !current);
  }
}
