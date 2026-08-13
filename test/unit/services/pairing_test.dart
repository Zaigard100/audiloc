import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/repositories/devices_repository.dart';
import 'package:audiloc/services/sync/discovery/discovered_peer.dart';
import 'package:audiloc/services/sync/metadata/metadata_sync_service.dart';
import 'package:audiloc/services/sync/pairing/pairing_client.dart';
import 'package:audiloc/services/sync/pairing/pairing_models.dart';
import 'package:audiloc/services/sync/pairing/pairing_server.dart';
import 'package:audiloc/services/sync/pairing/pairing_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real (non-mocked) HTTP round-trips for the pairing handshake — the
/// built-in replacement for the old "any peer on the LAN auto-syncs"
/// behavior. See docs/adr/0011-mutual-pairing-confirmation.md and, for
/// the profile-hash filtering in `PairingService`,
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md.
void main() {
  group('PairingServer/PairingClient protocol', () {
    late PairingServer server;
    const port = 8562;

    setUp(() async {
      server = PairingServer(port: port);
      await server.start();
    });

    tearDown(() => server.dispose());

    test("a request lands on the server with the sender's real socket address", () async {
      final received = server.requests.first.timeout(const Duration(seconds: 5));

      await PairingClient().sendRequest(
        host: '127.0.0.1',
        port: port,
        fromId: 'peer-1',
        fromName: 'Peer Phone',
        profileHash: 'hash-a',
      );

      final request = await received;
      expect(request.fromId, 'peer-1');
      expect(request.fromName, 'Peer Phone');
      expect(request.fromHost, '127.0.0.1');
      expect(request.profileHash, 'hash-a');
    });

    test('an accepted response carries accepted: true and the profile hash through', () async {
      final received = server.responses.first.timeout(const Duration(seconds: 5));

      await PairingClient().sendResponse(
        host: '127.0.0.1',
        port: port,
        fromId: 'peer-1',
        fromName: 'Peer Phone',
        accepted: true,
        profileHash: 'hash-a',
      );

      final response = await received;
      expect(response.accepted, isTrue);
      expect(response.profileHash, 'hash-a');
    });

    test('a rejected response carries accepted: false through', () async {
      final received = server.responses.first.timeout(const Duration(seconds: 5));

      await PairingClient().sendResponse(
        host: '127.0.0.1',
        port: port,
        fromId: 'peer-1',
        fromName: 'Peer Phone',
        accepted: false,
        profileHash: 'hash-a',
      );

      expect((await received).accepted, isFalse);
    });
  });

  group('PairingService', () {
    late AudilocDatabase db;
    late DevicesRepository devices;
    late MetadataSyncService metadataSync;
    late PairingServer server;
    late PairingService service;
    late List<IncomingPairingRequest> joinCalls;
    late bool canJoinDifferentProfile;

    // The response/request in these tests is deliberately pointed back at
    // this same device's own server — there's only one "device" here, but
    // it still exercises a real socket round-trip for everything
    // PairingService does with the wire, just talking to itself.
    const pairingPort = 8563;
    const metadataPort = 8564;
    const selfProfileHash = 'hash-self';

    setUp(() async {
      db = await AudilocDatabase.openInMemory();
      devices = DevicesRepository(db.crdt);
      metadataSync = MetadataSyncService(crdt: db.crdt, devicesRepository: devices, port: metadataPort);
      server = PairingServer(port: pairingPort);
      await server.start();
      joinCalls = [];
      // Default: no "Ждать сопряжения" in progress — matches most
      // devices most of the time (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md).
      canJoinDifferentProfile = false;
      service = PairingService(
        server: server,
        client: PairingClient(),
        devicesRepository: devices,
        metadataSyncService: metadataSync,
        selfId: db.nodeId,
        selfName: 'This Device',
        selfProfileHash: selfProfileHash,
        onJoinDifferentProfile: (request) async => joinCalls.add(request),
        canJoinDifferentProfile: () async => canJoinDifferentProfile,
        pairingPort: pairingPort,
        metadataSyncPort: metadataPort,
      );
    });

    tearDown(() async {
      await service.dispose();
      await metadataSync.dispose();
      await server.dispose();
      await db.close();
    });

    test('requestPairing sends this device\'s own id, name and profile hash', () async {
      final echoed = server.requests.first.timeout(const Duration(seconds: 5));

      await service
          .requestPairing(const DiscoveredPeer(deviceId: 'x', name: 'X', host: '127.0.0.1', port: 1234));

      final request = await echoed;
      expect(request.fromId, db.nodeId);
      expect(request.fromName, 'This Device');
      expect(request.profileHash, selfProfileHash);
    });

    test('approve() with a matching profile hash pairs the requester directly, without joining anything',
        () async {
      const request = IncomingPairingRequest(
        fromId: 'peer-9',
        fromName: 'Peer',
        fromHost: '127.0.0.1',
        profileHash: selfProfileHash,
      );
      final echoedResponse = server.responses.first.timeout(const Duration(seconds: 5));

      await service.approve(request);

      final paired = await devices.byId('peer-9');
      expect(paired, isNotNull);
      expect(paired!.name, 'Peer');
      expect((await echoedResponse).accepted, isTrue);
      expect(joinCalls, isEmpty, reason: 'same profile — no need to switch anything');
    });

    test(
        'approve() with a *different* profile hash defers entirely to onJoinDifferentProfile — no '
        'response, no pairing, from *this* (about-to-be-stale) identity (regression: a premature '
        "response here left the requester with a ghost device entry under the old identity's "
        'name that nothing ever cleaned up — docs/adr/0019-pairing-identity-and-cover-cache-fixes.md)',
        () async {
      const request = IncomingPairingRequest(
        fromId: 'peer-9',
        fromName: 'Peer',
        fromHost: '127.0.0.1',
        profileHash: 'hash-other',
      );
      final responses = <bool>[];
      server.responses.listen((r) => responses.add(r.accepted));

      await service.approve(request);

      expect(await devices.byId('peer-9'), isNull, reason: 'not paired into the current profile');
      expect(joinCalls, [request]);
      // Give any (unexpected) response a moment to arrive before asserting
      // none did — approve() must not answer under an identity that's
      // about to become permanently stale.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(responses, isEmpty);
    });

    test(
        're-calling approve() on a *new* session after onJoinDifferentProfile switches profiles '
        'responds and pairs correctly, exactly once, under the new identity — the actual '
        'end-to-end flow AudilocApp._joinProfileForPairing drives', () async {
      const request = IncomingPairingRequest(
        fromId: 'peer-9',
        fromName: 'Peer',
        fromHost: '127.0.0.1',
        profileHash: 'hash-other',
      );
      final echoedResponse = server.responses.first.timeout(const Duration(seconds: 5));

      // First call: different profile, defers — nothing happens yet.
      await service.approve(request);
      // Simulates AudilocApp switching profiles and building a *new*
      // PairingService whose selfProfileHash now matches the request
      // (that's the whole point of the switch) — same server/devices/
      // metadataSync here for simplicity, a real switch would use a
      // fresh database too, but that's orthogonal to what this is
      // testing: that re-approving answers and pairs exactly once.
      final newSession = PairingService(
        server: server,
        client: PairingClient(),
        devicesRepository: devices,
        metadataSyncService: metadataSync,
        selfId: db.nodeId,
        selfName: 'This Device',
        selfProfileHash: request.profileHash,
        onJoinDifferentProfile: (_) async => fail('should not recurse — hash matches now'),
        canJoinDifferentProfile: () async => false,
        pairingPort: pairingPort,
        metadataSyncPort: metadataPort,
      );
      addTearDown(newSession.dispose);

      await newSession.approve(request);

      final paired = await devices.byId('peer-9');
      expect(paired, isNotNull);
      expect(paired!.name, 'Peer');
      expect((await echoedResponse).accepted, isTrue);
    });

    test(
        'a different-profile request is auto-declined and never reaches incomingRequests when '
        "canJoinDifferentProfile is false — nothing for the user to approve, so no dialog "
        '(docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md)', () async {
      final seen = <IncomingPairingRequest>[];
      service.incomingRequests.listen(seen.add);
      final echoedResponse = server.responses.first.timeout(const Duration(seconds: 5));

      await PairingClient().sendRequest(
        host: '127.0.0.1',
        port: pairingPort,
        fromId: 'peer-9',
        fromName: 'Peer',
        profileHash: 'hash-other',
      );

      expect((await echoedResponse).accepted, isFalse);
      // Give the (non-)event a moment before asserting it never arrived.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(seen, isEmpty);
      expect(joinCalls, isEmpty);
      expect(await devices.byId('peer-9'), isNull);
    });

    test(
        'a different-profile request reaches incomingRequests when canJoinDifferentProfile is '
        'true (the "Ждать сопряжения" placeholder waiting to join another profile)', () async {
      canJoinDifferentProfile = true;
      final seen = <IncomingPairingRequest>[];
      service.incomingRequests.listen(seen.add);

      await PairingClient().sendRequest(
        host: '127.0.0.1',
        port: pairingPort,
        fromId: 'peer-9',
        fromName: 'Peer',
        profileHash: 'hash-other',
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(seen, hasLength(1));
      expect(seen.single.fromId, 'peer-9');
    });

    test('reject() does not pair, but still answers with accepted: false', () async {
      const request = IncomingPairingRequest(
        fromId: 'peer-9',
        fromName: 'Peer',
        fromHost: '127.0.0.1',
        profileHash: selfProfileHash,
      );
      final echoedResponse = server.responses.first.timeout(const Duration(seconds: 5));

      await service.reject(request);

      expect(await devices.byId('peer-9'), isNull);
      expect((await echoedResponse).accepted, isFalse);
    });

    test('an accepted response to a request we sent pairs it on our side too, regardless of its hash',
        () async {
      // Simulates the other device answering "yes" to a request this
      // service sent earlier — PairingService listens for this on its
      // own server's responses stream. We're the requester, so our own
      // profile is authoritative by convention — the response's hash is
      // never even inspected.
      await PairingClient().sendResponse(
        host: '127.0.0.1',
        port: pairingPort,
        fromId: 'peer-42',
        fromName: 'Peer 42',
        accepted: true,
        profileHash: 'hash-other',
      );

      await devices
          .watchAll()
          .map((all) => all.map((d) => d.id))
          .firstWhere((ids) => ids.contains('peer-42'))
          .timeout(const Duration(seconds: 5));
      expect(joinCalls, isEmpty, reason: 'the requester never switches profiles');
    });

    test('a rejected response to a request we sent does not pair', () async {
      await PairingClient().sendResponse(
        host: '127.0.0.1',
        port: pairingPort,
        fromId: 'peer-43',
        fromName: 'Peer 43',
        accepted: false,
        profileHash: selfProfileHash,
      );

      // Nothing to await for a non-event — give it a beat, then assert.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await devices.byId('peer-43'), isNull);
    });
  });
}
