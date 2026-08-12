import 'dart:async';
import 'dart:io';

/// Starts and monitors Syncthing as an external process (ТЗ п.9 risk note:
/// on desktop this just runs the system/bundled `syncthing` binary; on
/// Android it would need to run as a foreground service — see
/// docs/roadmap.md, out of scope for this MVP pass).
///
/// AudiLoc doesn't manage Syncthing's own config file directly; it talks to
/// the already-running instance through [SyncthingClient]'s REST API.
class SyncthingProcessManager {
  SyncthingProcessManager({this.executable = 'syncthing'});

  final String executable;
  Process? _process;

  bool get isRunning => _process != null;

  /// Launches `syncthing serve --no-browser --home <homeDir>`. Returns
  /// false (rather than throwing) when the binary can't be found or
  /// started, so callers can degrade gracefully — file sync is a bonus on
  /// top of the offline-first app, never a blocker (ТЗ п.7).
  Future<bool> start({required String homeDir}) async {
    if (_process != null) return true;
    try {
      final process = await Process.start(
        executable,
        ['serve', '--no-browser', '--home', homeDir],
        runInShell: true,
      );
      _process = process;
      unawaited(process.exitCode.then((_) => _process = null));
      return true;
    } on ProcessException {
      return false;
    }
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    process.kill();
    await process.exitCode;
    _process = null;
  }
}
