import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../services/remote_control/remote_control_client.dart';
import '../../../services/remote_control/remote_control_models.dart';
import 'devices_providers.dart';

/// Owns a single [RemoteControlClient] connection to [deviceId]'s
/// `RemoteControlServer`, and exposes the play/pause/next/previous/
/// loadAndPlay methods `DeviceTile` calls directly — see
/// docs/adr/0030-remote-playback-control.md. `autoDispose` + `family`:
/// each controlled device gets its own connection, alive only while
/// something actually watches this provider (i.e. its `DeviceTile` is on
/// screen) — no socket lingers in the background once the user navigates
/// away.
class RemoteControlController {
  RemoteControlController({required this.client});

  final RemoteControlClient client;

  void play() => client.play();
  void pause() => client.pause();
  void next() => client.next();
  void previous() => client.previous();
  void loadAndPlay(List<String> trackIds, int startIndex, Duration position) =>
      client.loadAndPlay(trackIds, startIndex, position);
}

final remoteControlControllerProvider =
    Provider.autoDispose.family<RemoteControlController, String>((ref, deviceId) {
  final client = RemoteControlClient();
  ref.onDispose(client.dispose);
  return RemoteControlController(client: client);
});

enum RemoteControlStatus { connecting, accepted, rejected }

class RemoteControlConnection {
  const RemoteControlConnection(this.status, this.state);

  final RemoteControlStatus status;
  final RemoteState? state;
}

/// Drives [remoteControlControllerProvider]'s connection attempt and
/// exposes its live status/state to the UI — kept separate from the
/// controller itself so `DeviceTile` can call control methods
/// synchronously (`ref.read(remoteControlControllerProvider(id))`)
/// without waiting on this stream.
final remoteControlConnectionProvider =
    StreamProvider.autoDispose.family<RemoteControlConnection, String>((ref, deviceId) async* {
  // `.select` on just this device's entry, not the whole nearby-peers
  // map — an unrelated peer coming online/offline elsewhere shouldn't
  // tear down and reconnect this socket.
  final peer = ref.watch(nearbyPeersProvider.select((async) => async.value?[deviceId]));
  if (peer == null) {
    yield const RemoteControlConnection(RemoteControlStatus.rejected, null);
    return;
  }

  final self = ref.watch(selfDeviceProvider);
  final controller = ref.watch(remoteControlControllerProvider(deviceId));

  yield const RemoteControlConnection(RemoteControlStatus.connecting, null);
  final accepted = await controller.client.connect(
    host: peer.host,
    port: remoteControlPort,
    selfId: self.id,
    selfName: self.name,
  );
  if (!accepted) {
    yield const RemoteControlConnection(RemoteControlStatus.rejected, null);
    return;
  }

  yield* controller.client.states.map(
    (state) => RemoteControlConnection(RemoteControlStatus.accepted, state),
  );
});
