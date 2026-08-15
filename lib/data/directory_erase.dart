import 'dart:io';

/// Best-effort recursive delete: removes every entry it can rather than
/// giving up the moment *one* can't be removed. A single
/// `Directory.delete(recursive: true)` call aborts entirely on its first
/// error — one locked/busy file (a leftover open handle from something
/// that was recently reading/writing inside this tree, say) would
/// otherwise leave the rest of the tree sitting there untouched for no
/// reason. Rethrows only after the whole tree has been attempted, so a
/// caller that lets the error propagate still ends up with the smallest
/// possible leftover mess, not the largest.
///
/// Shared by [ProfilesStore.delete] (one profile's directory) and the
/// Settings "Стереть все данные" flow (the whole app support directory —
/// see docs/adr/0028-settings-screen-and-theming.md) — same failure mode,
/// same fix, no reason to duplicate it.
Future<void> eraseDirectoryBestEffort(Directory dir) async {
  if (!await dir.exists()) return;
  Object? firstError;
  await for (final entity in dir.list(followLinks: false)) {
    try {
      if (entity is Directory) {
        await eraseDirectoryBestEffort(entity);
      } else {
        await entity.delete();
      }
    } catch (error) {
      firstError ??= error;
    }
  }
  try {
    await dir.delete();
  } catch (error) {
    firstError ??= error;
  }
  if (firstError != null) throw firstError;
}
