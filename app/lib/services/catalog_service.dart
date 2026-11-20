import 'package:http/http.dart' as http;

import '../models/game_entry.dart';
import 'storage_service.dart';

class CatalogService {
  CatalogService({StorageService? storage})
      : _storage = storage ?? StorageService.instance;

  final StorageService _storage;

  Future<List<GameEntry>> loadCatalog({
    required String catalogUrl,
    bool forceRefresh = false,
  }) async {
    final cacheFile = await _storage.getCatalogCacheFile();
    if (!forceRefresh && await cacheFile.exists()) {
      try {
        final cached = await cacheFile.readAsString();
        return GameEntry.parseCatalogJson(cached);
      } catch (_) {
        // Fall through to remote fetch if cache is corrupted.
      }
    }

    final response = await http
        .get(Uri.parse(catalogUrl))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('获取游戏目录失败 (HTTP ${response.statusCode})');
    }

    final body = response.body;
    final parsed = GameEntry.parseCatalogJson(body);
    await cacheFile.writeAsString(body, flush: true);
    return parsed;
  }
}
