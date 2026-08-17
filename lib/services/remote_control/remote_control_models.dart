/// Wire messages for `RemoteControlServer`/`RemoteControlClient` — plain
/// JSON over a single `dart:io` `WebSocket` per connection, one connection
/// per controlling device. See docs/adr/0030-remote-playback-control.md.

/// Live playback snapshot pushed by the server to a connected, permitted
/// controller. `trackId`/`title`/`artist` are all `null` when nothing is
/// loaded — a valid, common state, not an error.
class RemoteState {
  const RemoteState({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.queueTrackIds,
    required this.queueIndex,
  });

  final String? trackId;
  final String? title;
  final String? artist;
  final int positionMs;
  final int durationMs;
  final bool isPlaying;
  final bool shuffleEnabled;

  /// `PlaybackRepeatMode.name` — kept as a plain string here (rather than
  /// importing `player_service.dart`'s enum) so this models file has no
  /// dependency on the playback layer, same as everything else here.
  final String repeatMode;

  /// The controlled device's *whole* current queue, in play order — not
  /// just [trackId] — so a controller pulling playback back onto itself
  /// (docs/adr/0033-playback-ownership-and-handoff.md) can restore the
  /// full queue, not a single-track dead end for its own next/previous.
  /// Same "whole queue, not just one track" lesson `RemoteLoadAndPlay`
  /// already applies in the other direction (ADR 0030).
  final List<String> queueTrackIds;

  /// [trackId]'s position in [queueTrackIds] — `-1` if not found (e.g.
  /// nothing loaded).
  final int queueIndex;

  Map<String, Object?> toJson() => {
        'type': 'state',
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'isPlaying': isPlaying,
        'shuffleEnabled': shuffleEnabled,
        'repeatMode': repeatMode,
        'queueTrackIds': queueTrackIds,
        'queueIndex': queueIndex,
      };

  factory RemoteState.fromJson(Map<String, Object?> json) => RemoteState(
        trackId: json['trackId'] as String?,
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        positionMs: json['positionMs'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
        isPlaying: json['isPlaying'] as bool? ?? false,
        shuffleEnabled: json['shuffleEnabled'] as bool? ?? false,
        repeatMode: json['repeatMode'] as String? ?? 'all',
        queueTrackIds:
            json['queueTrackIds'] is List ? (json['queueTrackIds']! as List).cast<String>() : const [],
        queueIndex: json['queueIndex'] as int? ?? -1,
      );
}

/// What a controller can ask the controlled device to do. `loadAndPlay`
/// deliberately carries only track ids + a position, never a file — the
/// target device must already have each file locally
/// (`Track.isAvailableLocally`); there's no live audio streaming here,
/// matching how every other part of this app treats "the file isn't here
/// yet" (see docs/adr/0010-built-in-file-transfer.md). It carries the
/// *whole* queue the controller had loaded, not just the one track being
/// jumped to — a single-track queue would leave `next`/`previous`
/// (docs/adr/0030-remote-playback-control.md) with nothing to move to.
sealed class RemoteCommand {
  const RemoteCommand();

  Map<String, Object?> toJson();

  static RemoteCommand? fromJson(Map<String, Object?> json) => switch (json['action']) {
        'play' => const RemotePlay(),
        'pause' => const RemotePause(),
        'next' => const RemoteNext(),
        'previous' => const RemotePrevious(),
        'seek' when json['positionMs'] is int => RemoteSeek(positionMs: json['positionMs']! as int),
        'setShuffle' when json['enabled'] is bool => RemoteSetShuffle(enabled: json['enabled']! as bool),
        'setRepeatMode' when json['mode'] is String => RemoteSetRepeatMode(mode: json['mode']! as String),
        'loadAndPlay' when json['trackIds'] is List => RemoteLoadAndPlay(
            trackIds: (json['trackIds']! as List).cast<String>(),
            startIndex: json['startIndex'] as int? ?? 0,
            positionMs: json['positionMs'] as int? ?? 0,
          ),
        _ => null,
      };
}

class RemotePlay extends RemoteCommand {
  const RemotePlay();
  @override
  Map<String, Object?> toJson() => const {'type': 'command', 'action': 'play'};
}

class RemotePause extends RemoteCommand {
  const RemotePause();
  @override
  Map<String, Object?> toJson() => const {'type': 'command', 'action': 'pause'};
}

class RemoteNext extends RemoteCommand {
  const RemoteNext();
  @override
  Map<String, Object?> toJson() => const {'type': 'command', 'action': 'next'};
}

class RemotePrevious extends RemoteCommand {
  const RemotePrevious();
  @override
  Map<String, Object?> toJson() => const {'type': 'command', 'action': 'previous'};
}

/// Added for the full player screen's remote-control mode
/// (docs/adr/0033-playback-ownership-and-handoff.md) — the Devices tab's
/// inline quick-controls (ADR 0030) deliberately don't expose seeking
/// (display-only progress bar), so this was never needed there.
class RemoteSeek extends RemoteCommand {
  const RemoteSeek({required this.positionMs});
  final int positionMs;
  @override
  Map<String, Object?> toJson() => {'type': 'command', 'action': 'seek', 'positionMs': positionMs};
}

class RemoteSetShuffle extends RemoteCommand {
  const RemoteSetShuffle({required this.enabled});
  final bool enabled;
  @override
  Map<String, Object?> toJson() => {'type': 'command', 'action': 'setShuffle', 'enabled': enabled};
}

/// [mode] is `PlaybackRepeatMode.name` — see [RemoteState.repeatMode].
class RemoteSetRepeatMode extends RemoteCommand {
  const RemoteSetRepeatMode({required this.mode});
  final String mode;
  @override
  Map<String, Object?> toJson() => {'type': 'command', 'action': 'setRepeatMode', 'mode': mode};
}

class RemoteLoadAndPlay extends RemoteCommand {
  const RemoteLoadAndPlay({required this.trackIds, required this.startIndex, required this.positionMs});

  final List<String> trackIds;
  final int startIndex;
  final int positionMs;

  @override
  Map<String, Object?> toJson() => {
        'type': 'command',
        'action': 'loadAndPlay',
        'trackIds': trackIds,
        'startIndex': startIndex,
        'positionMs': positionMs,
      };
}
