import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/game_entry.dart';
import 'storage_service.dart';

class DownloadService {
  DownloadService({StorageService? storage})
      : _storage = storage ?? StorageService.instance;

  final StorageService _storage;

  /// Downloads a game's .zip archive, verifies SHA256 if provided, and stores it locally.
  Future<File> downloadGame({
    required GameEntry game,
    required String binBaseUrl,
    void Function(double progress)? onProgress,
  }) async {
    final destFile = await _storage.getGameZipFile(game.identifier);
    final tempFile = File('${destFile.path}.part');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final url = game.downloadUrl(binBaseUrl);
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('下载失败 (HTTP ${response.statusCode})');
      }

      final totalBytes = response.contentLength ?? game.filesize ?? 0;
      var receivedBytes = 0;

      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && onProgress != null) {
            onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (game.sha256 != null && game.sha256!.isNotEmpty) {
        final digest = await sha256.bind(tempFile.openRead()).first;
        if (digest.toString().toLowerCase() != game.sha256!.toLowerCase()) {
          await tempFile.delete();
          throw Exception('文件 SHA256 校验失败，请重试或更换下载源');
        }
      }

      if (await destFile.exists()) {
        await destFile.delete();
      }
      return tempFile.rename(destFile.path);
    } finally {
      client.close();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Copies a user-selected local .zip file into the managed games directory.
  Future<GameEntry> importLocalZip(File sourceFile) async {
    final id = p.basenameWithoutExtension(sourceFile.path);
    final destFile = await _storage.getGameZipFile(id);
    await sourceFile.copy(destFile.path);
    final stat = await destFile.stat();
    return GameEntry.localImport(identifier: id, filesize: stat.size);
  }
}
