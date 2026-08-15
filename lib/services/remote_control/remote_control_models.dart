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
  });

  final String? trackId;
  final String? title;
  final String? artist;
  final int positionMs;
  final int durationMs;
  final bool isPlaying;

  Map<String, Object?> toJson() => {
        'type': 'state',
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'isPlaying': isPlaying,
      };

  factory RemoteState.fromJson(Map<String, Object?> json) => RemoteState(
        trackId: json['trackId'] as String?,
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        positionMs: json['positionMs'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
        isPlaying: json['isPlaying'] as bool? ?? false,
      );
}

/// What a controller can ask the controlled device to do. `loadAndPlay`
/// deliberately carries only a track id + position, never a file — the
/// target device must already have the file locally
/// (`Track.isAvailableLocally`); there's no live audio streaming here,
/// matching how every other part of this app treats "the file isn't here
/// yet" (see docs/adr/0010-built-in-file-transfer.md).
sealed class RemoteCommand {
  const RemoteCommand();

  Map<String, Object?> toJson();

  static RemoteCommand? fromJson(Map<String, Object?> json) => switch (json['action']) {
        'play' => const RemotePlay(),
        'pause' => const RemotePause(),
        'next' => const RemoteNext(),
        'previous' => const RemotePrevious(),
        'loadAndPlay' when json['trackId'] is String => RemoteLoadAndPlay(
            trackId: json['trackId']! as String,
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

class RemoteLoadAndPlay extends RemoteCommand {
  const RemoteLoadAndPlay({required this.trackId, required this.positionMs});

  final String trackId;
  final int positionMs;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'command', 'action': 'loadAndPlay', 'trackId': trackId, 'positionMs': positionMs};
}
