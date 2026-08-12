/// A batch of CRDT records exchanged with one peer, as reported by
/// `crdt_sync`'s `onChangesetReceived`/`onChangesetSent` callbacks.
///
/// This is the raw material for the "синхронизировано N изменений" badge
/// from ТЗ п.6.6.
class SyncStats {
  const SyncStats({required this.deviceId, required this.recordCounts});

  final String deviceId;

  /// Records affected, keyed by table name.
  final Map<String, int> recordCounts;

  int get totalRecords => recordCounts.values.fold(0, (a, b) => a + b);
}
