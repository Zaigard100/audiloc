/// One track being offered as part of an [IncomingShareOffer] — display
/// info only, taken from the sender's own local `Track` row. Not
/// authoritative: the actual import re-extracts tags straight from the
/// downloaded file (see `ShareService.acceptOffer`), so a stale or
/// mismatched preview here can never corrupt what actually gets imported.
class ShareItemPreview {
  const ShareItemPreview({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
  });

  final String trackId;
  final String? title;
  final String? artist;
  final String? album;
}

/// A "Поделиться" offer received from another device — one track, or a
/// whole album's worth, regardless of whether the two devices' profiles
/// have anything to do with each other. See
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md — this is
/// the replacement for letting pairing itself move content between
/// independent profiles.
class IncomingShareOffer {
  const IncomingShareOffer({
    required this.fromId,
    required this.fromName,
    required this.fromHost,
    required this.items,
  });

  final String fromId;
  final String fromName;

  /// Taken from the request's actual socket address, not anything the
  /// request body claims — see [ShareServer]. This is where
  /// `ShareService.acceptOffer` downloads the files from.
  final String fromHost;

  final List<ShareItemPreview> items;
}

/// The other side's answer to an offer *we* sent via
/// [ShareService.shareTrack]/[ShareService.shareAlbum].
class ShareResponse {
  const ShareResponse({
    required this.fromId,
    required this.fromName,
    required this.fromHost,
    required this.accepted,
  });

  final String fromId;
  final String fromName;
  final String fromHost;
  final bool accepted;
}
