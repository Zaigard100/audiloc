/// What kind of list [PlaybackState.trackId] was playing from — enough
/// to rebuild the same ordered queue on another device (or after a
/// restart) without storing the whole track list itself, which would
/// just go stale the moment the underlying list changes.
enum PlaybackQueueType { library, favorites, playlist }

/// The single most-recently-paused "now playing" position for this
/// profile — synced like any other CRDT row, see
/// docs/adr/0029-playback-state-sync.md. Deliberately doesn't carry a
/// `Track`/`Playlist` object, only ids — resolving those (and deciding
/// whether they're even resolvable yet on this device) is
/// [PlaybackStateRepository]'s caller's job, not this model's.
class PlaybackState {
  const PlaybackState({
    required this.trackId,
    required this.positionMs,
    required this.queueType,
    this.playlistId,
    required this.deviceId,
    required this.deviceName,
  });

  final String trackId;
  final int positionMs;
  final PlaybackQueueType queueType;

  /// Only set when [queueType] is [PlaybackQueueType.playlist].
  final String? playlistId;

  /// Whichever device last paused — this profile's own [Device.id] at
  /// the time of writing. Used to tell "this is our own write, already
  /// reflected locally" apart from "a peer just paused something".
  final String deviceId;
  final String deviceName;

  Duration get position => Duration(milliseconds: positionMs);

  factory PlaybackState.fromRow(Map<String, Object?> row) => PlaybackState(
        trackId: row['track_id']! as String,
        positionMs: row['position_ms']! as int,
        queueType: PlaybackQueueType.values.byName(row['queue_type']! as String),
        playlistId: row['playlist_id'] as String?,
        deviceId: row['device_id']! as String,
        deviceName: row['device_name']! as String,
      );

  /// Plain-file encoding for `LocalPlaybackStateStore` — a *local*,
  /// unsynced counterpart to [fromRow]/the CRDT `playback_state` table.
  /// See docs/adr/0029-playback-state-sync.md.
  Map<String, Object?> toJson() => {
        'trackId': trackId,
        'positionMs': positionMs,
        'queueType': queueType.name,
        'playlistId': playlistId,
        'deviceId': deviceId,
        'deviceName': deviceName,
      };

  factory PlaybackState.fromJson(Map<String, Object?> json) => PlaybackState(
        trackId: json['trackId']! as String,
        positionMs: json['positionMs']! as int,
        queueType: PlaybackQueueType.values.byName(json['queueType']! as String),
        playlistId: json['playlistId'] as String?,
        deviceId: json['deviceId']! as String,
        deviceName: json['deviceName']! as String,
      );
}
