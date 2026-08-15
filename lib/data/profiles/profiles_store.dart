import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../directory_erase.dart';
import 'profile.dart';

/// Local registry of profiles living under [appSupportDir] — which
/// profile directories exist on *this* device, and which one was last
/// active. See docs/adr/0013-account-profiles.md.
///
/// Each profile's actual data (CRDT database, cached covers, downloaded
/// audio) lives in its own subdirectory
/// (`<appSupportDir>/profiles/<id>/...`) — this class only manages the
/// list itself (`<appSupportDir>/profiles.json`), never a profile's
/// contents.
class ProfilesStore {
  ProfilesStore(this.appSupportDir);

  final Directory appSupportDir;
  static const _uuid = Uuid();

  File get _registryFile => File(p.join(appSupportDir.path, 'profiles.json'));

  Directory profileDir(String id) => Directory(p.join(appSupportDir.path, 'profiles', id));

  Future<List<Profile>> list() async => (await _read()).profiles;

  Future<String?> activeProfileId() async => (await _read()).activeProfileId;

  Future<void> setActiveProfileId(String id) async {
    final state = await _read();
    await _write(state.copyWith(activeProfileId: id));
  }

  /// [profileHash], if given, joins this profile to an existing shared
  /// identity (docs/adr/0015) — used when this device is adopting a
  /// profile it was just paired into. Left unset for the ordinary "brand
  /// new profile" case, where a fresh hash is generated.
  Future<Profile> create(String name, {String? profileHash}) async {
    final profile = Profile(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
      profileHash: profileHash ?? _uuid.v4(),
    );
    await profileDir(profile.id).create(recursive: true);
    final state = await _read();
    await _write(state.copyWith(profiles: [...state.profiles, profile]));
    return profile;
  }

  /// Finds a profile this device already has a local copy of, by its
  /// shared [profileHash] — see docs/adr/0015-profile-identity-in-pairing.md.
  Future<Profile?> findByHash(String hash) async {
    for (final profile in await list()) {
      if (profile.profileHash == hash) return profile;
    }
    return null;
  }

  Future<void> rename(String id, String name) async {
    final state = await _read();
    await _write(state.copyWith(
      profiles: [for (final p in state.profiles) if (p.id == id) p.copyWith(name: name) else p],
    ));
  }

  /// Unregisters the profile *and* erases its entire directory — the CRDT
  /// database, paired devices, cached covers, downloaded audio,
  /// everything. Irreversible by design (docs/adr/0018-delete-profile.md)
  /// — the UI is what's responsible for a serious confirmation before
  /// calling this, and for never calling it on the currently *active*
  /// profile: its database file is open and in use, so deleting it out
  /// from under the running session would corrupt more than just that
  /// profile (switch away first — `ProfileSwitcherSheet` enforces this).
  Future<void> delete(String id) async {
    final state = await _read();
    await _write(state.copyWith(
      profiles: [for (final p in state.profiles) if (p.id != id) p],
      activeProfileId: state.activeProfileId == id ? null : state.activeProfileId,
    ));
    await eraseDirectoryBestEffort(profileDir(id));
  }

  /// True only for a genuinely fresh install: no profiles registered yet
  /// and nothing to migrate from a pre-accounts install either. `AudilocApp`
  /// checks this *before* calling [resolveActiveProfileId] so it can ask
  /// for a name instead of silently defaulting to one — someone upgrading
  /// from before profiles existed still gets their library back with zero
  /// prompts (see [resolveActiveProfileId]), this is only for the case
  /// where there's nothing to preserve either way.
  Future<bool> needsInitialSetup() async {
    final state = await _read();
    if (state.profiles.isNotEmpty) return false;
    return !await File(p.join(appSupportDir.path, 'audiloc.db')).exists();
  }

  /// Always returns a real profile id — called once at startup so the
  /// rest of the app never has to handle "no profile chosen yet" as a
  /// UI state. In order:
  /// 1. The last-active profile, if it still exists.
  /// 2. Any other known profile (covers deleting the active one).
  /// 3. A migrated copy of the pre-accounts flat `audiloc.db` (and its
  ///    `covers`/`synced_music` caches), if one exists — so upgrading
  ///    from a version before this feature never loses a library or its
  ///    paired devices.
  /// 4. A fresh, silently-created default profile — a fallback for
  ///    callers that skip the [needsInitialSetup] check; `AudilocApp`
  ///    itself asks for a name instead of ever hitting this branch.
  Future<String> resolveActiveProfileId() async {
    final state = await _read();
    if (state.activeProfileId != null && state.profiles.any((p) => p.id == state.activeProfileId)) {
      return state.activeProfileId!;
    }
    if (state.profiles.isNotEmpty) {
      final id = state.profiles.first.id;
      await setActiveProfileId(id);
      return id;
    }

    final legacyDb = File(p.join(appSupportDir.path, 'audiloc.db'));
    final isMigration = await legacyDb.exists();
    final profile = await create('Профиль 1');
    if (isMigration) {
      await legacyDb.rename(p.join(profileDir(profile.id).path, 'audiloc.db'));
      await _moveIfExists(
        Directory(p.join(appSupportDir.path, 'covers')),
        Directory(p.join(profileDir(profile.id).path, 'covers')),
      );
      await _moveIfExists(
        Directory(p.join(appSupportDir.path, 'synced_music')),
        Directory(p.join(profileDir(profile.id).path, 'synced_music')),
      );
    }
    await setActiveProfileId(profile.id);
    return profile.id;
  }

  Future<void> _moveIfExists(Directory from, Directory to) async {
    if (!await from.exists()) return;
    if (await to.exists()) await to.delete(recursive: true);
    await from.rename(to.path);
  }

  Future<_RegistryState> _read() async {
    if (!await _registryFile.exists()) return const _RegistryState(profiles: [], activeProfileId: null);
    final json = jsonDecode(await _registryFile.readAsString()) as Map<String, Object?>;
    return _RegistryState(
      profiles: [
        for (final entry in json['profiles']! as List<Object?>) Profile.fromJson(entry! as Map<String, Object?>),
      ],
      activeProfileId: json['activeProfileId'] as String?,
    );
  }

  Future<void> _write(_RegistryState state) async {
    if (!await appSupportDir.exists()) await appSupportDir.create(recursive: true);
    await _registryFile.writeAsString(jsonEncode({
      'profiles': [for (final profile in state.profiles) profile.toJson()],
      'activeProfileId': state.activeProfileId,
    }));
  }
}

/// Sentinel distinguishing "activeProfileId not passed to copyWith, keep
/// the current value" from "explicitly passed null to clear it" (used by
/// [ProfilesStore.delete]) — a plain nullable parameter can't tell those
/// apart, and getting this wrong here would mean every [ProfilesStore.create]
/// or [ProfilesStore.rename] call silently forgets which profile was active.
const _unset = Object();

class _RegistryState {
  const _RegistryState({required this.profiles, required this.activeProfileId});

  final List<Profile> profiles;
  final String? activeProfileId;

  _RegistryState copyWith({List<Profile>? profiles, Object? activeProfileId = _unset}) => _RegistryState(
        profiles: profiles ?? this.profiles,
        activeProfileId: identical(activeProfileId, _unset) ? this.activeProfileId : activeProfileId as String?,
      );
}
