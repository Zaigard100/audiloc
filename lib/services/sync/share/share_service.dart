import 'dart:async';
import 'dart:io';

import '../../../data/models/track.dart';
import '../../library_import/library_import_service.dart';
import '../files/file_transfer_client.dart';
import 'share_client.dart';
import 'share_models.dart';
import 'share_server.dart';

/// Glues [ShareServer]/[ShareClient] to [FileTransferClient] and
/// [LibraryImportService]: turns "Поделиться" into an actual file
/// transfer and library import on the receiving side — without either
/// device needing to be paired, or belong to the same profile. See
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md.
///
/// Deliberately not transactional, same reasoning as `PairingService`: if
/// a response never arrives, the sender just sees nothing happen.
class ShareService {
  ShareService({
    required ShareServer server,
    required ShareClient client,
    required FileTransferClient fileTransferClient,
    required Future<LibraryImportService> Function() resolveImportService,
    required String selfId,
    required String selfName,
    this.sharePort = 8544,
    this.fileTransferPort = 8542,
  })  : _server = server,
        _client = client,
        _fileTransferClient = fileTransferClient,
        _resolveImportService = resolveImportService,
        _selfId = selfId,
        _selfName = selfName;

  final ShareServer _server;
  final ShareClient _client;
  final FileTransferClient _fileTransferClient;
  final Future<LibraryImportService> Function() _resolveImportService;
  final String _selfId;
  final String _selfName;
  final int sharePort;
  final int fileTransferPort;

  /// Offers waiting on *this* device's user to accept/decline — UI shows
  /// a dialog for each.
  Stream<IncomingShareOffer> get incomingOffers => _server.offers;

  /// The sender's own feedback on an offer it made — whether the other
  /// side accepted or declined. Purely informational (e.g. a SnackBar);
  /// nothing here drives further action, unlike pairing's responses.
  Stream<ShareResponse> get responses => _server.responses;

  Future<void> shareTrack({required String host, required int port, required Track track}) =>
      _sendOffer(host: host, port: port, items: [_preview(track)]);

  Future<void> shareAlbum({required String host, required int port, required List<Track> tracks}) =>
      _sendOffer(host: host, port: port, items: [for (final t in tracks) _preview(t)]);

  ShareItemPreview _preview(Track track) => ShareItemPreview(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
      );

  Future<void> _sendOffer({required String host, required int port, required List<ShareItemPreview> items}) =>
      _client.sendOffer(host: host, port: port, fromId: _selfId, fromName: _selfName, items: items);

  /// Downloads every item's audio file from the offerer and hands it to
  /// [LibraryImportService] — the same path a manual folder import takes,
  /// so tag extraction, content-hash dedup and local storage all come for
  /// free. Nothing is written to this device's `devices`/CRDT sync state;
  /// this is a one-shot file copy, not a pairing.
  Future<void> acceptOffer(IncomingShareOffer offer) async {
    await _client.sendResponse(
      host: offer.fromHost,
      port: sharePort,
      fromId: _selfId,
      fromName: _selfName,
      accepted: true,
    );

    final tempDir = await Directory.systemTemp.createTemp('audiloc_share_');
    try {
      final files = <File>[];
      for (final item in offer.items) {
        final path = await _fileTransferClient.download(
          host: offer.fromHost,
          port: fileTransferPort,
          trackId: item.trackId,
          destinationDir: tempDir,
        );
        files.add(File(path));
      }
      final importService = await _resolveImportService();
      await importService.importFiles(files);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<void> rejectOffer(IncomingShareOffer offer) => _client.sendResponse(
        host: offer.fromHost,
        port: sharePort,
        fromId: _selfId,
        fromName: _selfName,
        accepted: false,
      );
}
