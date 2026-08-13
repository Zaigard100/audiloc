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
  Future<String> download({
    required String host,
    required int port,
    required String trackId,
    required Directory destinationDir,
  }) async {
    final uri = 'http://$host:$port/tracks/$trackId';
    final partFile = File(p.join(destinationDir.path, '$trackId.part'));
    final alreadyHave = await partFile.exists() ? await partFile.length() : 0;

    final response = await _dio.download(
      uri,
      partFile.path,
      fileAccessMode: alreadyHave > 0 ? FileAccessMode.append : FileAccessMode.write,
      options: alreadyHave > 0 ? Options(headers: {'range': 'bytes=$alreadyHave-'}) : null,
    );

    final ext = response.headers.value('x-original-extension') ?? '';
    final finalFile = File(p.join(destinationDir.path, '$trackId$ext'));
    await partFile.rename(finalFile.path);
    return finalFile.path;
  }
}
