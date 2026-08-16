import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'playback_ownership_link.dart';

/// Dials another sync-enabled paired device's `PlaybackOwnershipServer`.
/// Returns `null` on rejection, connection failure, or no answer within
/// [timeout] — [PlaybackOwnershipCoordinator] is the only caller, and
/// treats every failure case the same way: don't open a link, the mesh
/// self-heals on the next discovery/heartbeat cycle. [remoteDeviceId] is
/// supplied by the caller (it already knows which peer it's dialing,
/// unlike the server side's handshake) — used only to label the
/// returned [PlaybackOwnershipLink]. See
/// docs/adr/0033-playback-ownership-and-handoff.md.
///
/// One persistent `listen()` for the whole connection, same
/// single-subscription reasoning as `playback_ownership_server.dart`:
/// the handshake reply is just the first message through it, and once
/// accepted the returned [PlaybackOwnershipLink] is constructed *inside*
/// this same callback and fed every message after via
/// [PlaybackOwnershipLink.handleIncoming].
Future<PlaybackOwnershipLink?> connectPlaybackOwnershipLink({
  required String host,
  required int port,
  required String selfId,
  required String selfName,
  required String remoteDeviceId,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    final socket = await WebSocket.connect('ws://$host:$port/playback-ownership').timeout(timeout);
    socket.add(jsonEncode({'type': 'hello', 'deviceId': selfId, 'name': selfName}));

    final handshake = Completer<bool>();
    PlaybackOwnershipLink? link;
    socket.listen(
      (raw) {
        if (!handshake.isCompleted) {
          final accepted = raw is String && _decodeType(raw) == 'accepted';
          if (accepted) {
            link = PlaybackOwnershipLink(remoteDeviceId: remoteDeviceId, socket: socket);
          }
          handshake.complete(accepted);
          return;
        }
        link?.handleIncoming(raw);
      },
      onDone: () => link?.handleClosed(),
      onError: (_) => link?.handleClosed(),
      cancelOnError: true,
    );

    final accepted = await handshake.future.timeout(timeout, onTimeout: () => false);
    if (!accepted) {
      await socket.close();
      return null;
    }
    return link;
  } catch (_) {
    return null;
  }
}

String? _decodeType(String raw) {
  try {
    return (jsonDecode(raw) as Map<String, Object?>)['type'] as String?;
  } catch (_) {
    return null;
  }
}
