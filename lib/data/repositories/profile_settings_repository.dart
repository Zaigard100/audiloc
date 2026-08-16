import 'package:sqlite_crdt/sqlite_crdt.dart';

/// CRUD over the `profile_settings` table — always exactly one row (`id =
/// 'current'`), the profile-wide counterpart to `AppSettingsStore`'s
/// device-level settings. See docs/adr/0032-unified-profile-sync-and-background-mode.md.
class ProfileSettingsRepository {
  ProfileSettingsRepository(this._crdt);

  final SqliteCrdt _crdt;

  static const _id = 'current';

  Stream<bool> watchSyncPlaybackEnabled() => _crdt
      .watch('SELECT sync_playback_enabled FROM profile_settings WHERE id = ?1 AND is_deleted = 0', () => [_id])
      .map((rows) => rows.isEmpty ? false : (rows.first['sync_playback_enabled']! as int) == 1);

  /// One-shot read, for call sites that need the current value without
  /// waiting for [watchSyncPlaybackEnabled]'s underlying CRDT watch to
  /// deliver its first emission — see `resume_playback_prompt.dart`.
  Future<bool> isSyncPlaybackEnabled() async {
    final rows = await _crdt
        .query('SELECT sync_playback_enabled FROM profile_settings WHERE id = ?1 AND is_deleted = 0', [_id]);
    if (rows.isEmpty) return false;
    return (rows.first['sync_playback_enabled']! as int) == 1;
  }

  Future<void> setSyncPlaybackEnabled(bool value) => _crdt.execute('''
        INSERT INTO profile_settings (id, sync_playback_enabled)
          VALUES (?1, ?2)
        ON CONFLICT (id) DO UPDATE SET
          sync_playback_enabled = excluded.sync_playback_enabled,
          is_deleted = 0
      ''', [_id, value ? 1 : 0]);
}
