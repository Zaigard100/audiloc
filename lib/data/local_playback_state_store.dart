import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models/playback_state.dart';

/// This device's own "last paused here" bookmark — a plain local file
/// inside [profileDir], deliberately **not** a CRDT table: unlike
/// `PlaybackStateRepository` (the cross-device-synced counterpart, see
/// docs/adr/0029-playback-state-sync.md), nothing here is ever synced to
/// another device or read from one — it exists purely so this device can
/// continue where it left off after its own restart, independent of
/// whether cross-device sync ("отправлять"/"принимать" в Настройках) is
/// even turned on. Profile-scoped (lives under `profileDir`, not
/// device-level `settings.json`) since the state itself only makes sense
/// relative to one profile's library.
class LocalPlaybackStateStore {
  LocalPlaybackStateStore(this.profileDir);

  final Directory profileDir;

  File get _file => File(p.join(profileDir.path, 'last_session.json'));

  Future<PlaybackState?> read() async {
    if (!await _file.exists()) return null;
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      return PlaybackState.fromJson(json);
    } catch (_) {
      // Corrupted or partially-written file (e.g. the process died mid-write)
      // — treat as "nothing saved" rather than crashing startup over a
      // bookmark that was never critical to begin with.
      return null;
    }
  }

  Future<void> write(PlaybackState state) async {
    if (!await profileDir.exists()) await profileDir.create(recursive: true);
    await _file.writeAsString(jsonEncode(state.toJson()));
  }
}
