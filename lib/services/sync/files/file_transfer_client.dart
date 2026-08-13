import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

/// Downloads one track's audio file from a peer's [FileTransferServer].
class FileTransferClient {
  FileTransferClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Downloads `http://$host:$port/tracks/$trackId` into
  /// `$destinationDir/$trackId<ext>`, where `<ext>` comes from the
  /// server's `X-Original-Extension` header. Resumes an interrupted
  /// download of the same track if a partial file is already there.
  /// Returns the saved file's final path.
  ///
  /// [onProgress], if given, is called with byte counts against the
  /// *whole file* (not just the remaining part of a resumed download) —
  /// `totalBytes` is `-1` if the server didn't send a length.
  Future<String> download({
    required String host,
    required int port,
    required String trackId,
    required Directory destinationDir,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final uri = 'http://$host:$port/tracks/$trackId';
    final partFile = File(p.join(destinationDir.path, '$trackId.part'));
    final alreadyHave = await partFile.exists() ? await partFile.length() : 0;

    final response = await _dio.download(
      uri,
      partFile.path,
      fileAccessMode: alreadyHave > 0 ? FileAccessMode.append : FileAccessMode.write,
      options: alreadyHave > 0 ? Options(headers: {'range': 'bytes=$alreadyHave-'}) : null,
      onReceiveProgress: onProgress == null
          ? null
          : (received, total) => onProgress(alreadyHave + received, total < 0 ? -1 : alreadyHave + total),
    );

    final ext = response.headers.value('x-original-extension') ?? '';
    final finalFile = File(p.join(destinationDir.path, '$trackId$ext'));
    await partFile.rename(finalFile.path);
    return finalFile.path;
  }
}
