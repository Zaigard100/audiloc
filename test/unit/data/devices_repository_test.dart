import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/repositories/devices_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudilocDatabase db;
  late DevicesRepository repository;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    repository = DevicesRepository(db.crdt);
  });

  tearDown(() => db.close());

  const device = Device(id: 'peer-1', name: 'Peer Phone', host: '192.168.1.50', syncPort: 8541);

  test('upsert then byId round-trips fields', () async {
    await repository.upsert(device);
    final fetched = await repository.byId(device.id);

    expect(fetched, isNotNull);
    expect(fetched!.name, 'Peer Phone');
    expect(fetched.host, '192.168.1.50');
    expect(fetched.syncPort, 8541);
  });

  test('byId returns null for an unpaired/unknown device', () async {
    expect(await repository.byId('unknown'), isNull);
  });

  test('watchAll only lists paired (not soft-deleted) devices', () async {
    await repository.upsert(device);
    final all = await repository.watchAll().first;
    expect(all.map((d) => d.id), [device.id]);
  });

  test(
      'delete unpairs the device: it drops out of watchAll/byId — the "отвязать" '
      'action a user takes from the Devices screen', () async {
    await repository.upsert(device);
    await repository.delete(device.id);

    expect(await repository.byId(device.id), isNull);
    expect(await repository.watchAll().first, isEmpty);
  });

  test('re-pairing after unpairing (upsert with the same id) works again', () async {
    await repository.upsert(device);
    await repository.delete(device.id);
    await repository.upsert(device);

    expect(await repository.byId(device.id), isNotNull);
  });
}
