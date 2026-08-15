import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../services/sync/share/share_models.dart';

/// Shown for an incoming "Поделиться" offer. The user needs to actually
/// see what's being offered — title and cover, not just a bare id —
/// before deciding whether to accept it into their library. The cover is
/// fetched ahead of that decision straight from the offerer's own
/// `FileTransferServer` (the same `/covers/<id>` route file sync already
/// uses — no pairing required, see
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md); the audio
/// itself is only downloaded once the user actually accepts.
Future<void> showShareOfferDialog(BuildContext context, WidgetRef ref, IncomingShareOffer offer) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ShareOfferDialog(offer: offer),
  );
}

class _ShareOfferDialog extends ConsumerStatefulWidget {
  const _ShareOfferDialog({required this.offer});

  final IncomingShareOffer offer;

  @override
  ConsumerState<_ShareOfferDialog> createState() => _ShareOfferDialogState();
}

class _ShareOfferDialogState extends ConsumerState<_ShareOfferDialog> {
  File? _cover;
  var _coverLoadFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCover());
  }

  Future<void> _loadCover() async {
    final item = widget.offer.items.first;
    try {
      final client = ref.read(fileTransferClientProvider);
      final tempDir = await Directory.systemTemp.createTemp('audiloc_share_preview_');
      final path = await client.downloadCover(
        host: widget.offer.fromHost,
        port: fileTransferPort,
        trackId: item.trackId,
        destinationDir: tempDir,
      );
      if (mounted) setState(() => _cover = File(path));
    } catch (_) {
      // No cover on the sender's side, or it went offline before this
      // finished — fine, just show a placeholder instead.
      if (mounted) setState(() => _coverLoadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final items = offer.items;
    final first = items.first;
    final l10n = context.l10n;
    final String description;
    if (items.length == 1) {
      description = l10n.shareOfferSingleTrack(offer.fromName);
    } else {
      final album = first.album;
      description = album != null
          ? l10n.shareOfferAlbum(offer.fromName, album, items.length)
          : l10n.shareOfferTracks(offer.fromName, items.length);
    }

    return AlertDialog(
      title: Text(l10n.shareOfferTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 96,
              height: 96,
              child: _cover != null
                  ? Image.file(_cover!, fit: BoxFit.cover)
                  : ColoredBox(
                      color: AppTheme.surfaceHigh,
                      child: Icon(
                        _coverLoadFailed ? Icons.music_note : Icons.hourglass_empty,
                        color: AppTheme.onSurfaceMuted,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            first.title ?? first.trackId,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (first.artist != null)
            Text(first.artist!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.onSurfaceMuted)),
          const SizedBox(height: 8),
          Text(description, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(shareServiceProvider).rejectOffer(offer);
            Navigator.of(context).pop();
          },
          child: Text(l10n.commonDecline),
        ),
        TextButton(
          onPressed: () {
            ref.read(shareServiceProvider).acceptOffer(offer);
            Navigator.of(context).pop();
          },
          child: Text(l10n.shareOfferAccept),
        ),
      ],
    );
  }
}
