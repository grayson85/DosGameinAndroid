import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.catalogUrl = defaultCatalogUrl,
    this.binBaseUrl = defaultBinBaseUrl,
    this.coverBaseUrl = defaultCoverBaseUrl,
    this.linearFilter = false,
    this.cyclesPreset = 'auto',
    this.soundFontFilename,
  });

  static const String defaultCatalogUrl =
      'https://raw.githubusercontent.com/rwv/chinese-dos-games/master/games.json';
  static const String defaultBinBaseUrl = 'https://dos-bin.zczc.cz/';
  static const String defaultCoverBaseUrl =
      'https://raw.githubusercontent.com/rwv/chinese-dos-games/master/img/';

  final String catalogUrl;
  final String binBaseUrl;
  final String coverBaseUrl;
  final bool linearFilter;
  final String cyclesPreset;
  final String? soundFontFilename;

  AppSettings copyWith({
    String? catalogUrl,
    String? binBaseUrl,
    String? coverBaseUrl,
    bool? linearFilter,
    String? cyclesPreset,
    String? soundFontFilename,
    bool clearSoundFont = false,
  }) {
    return AppSettings(
      catalogUrl: catalogUrl ?? this.catalogUrl,
      binBaseUrl: binBaseUrl ?? this.binBaseUrl,
      coverBaseUrl: coverBaseUrl ?? this.coverBaseUrl,
      linearFilter: linearFilter ?? this.linearFilter,
      cyclesPreset: cyclesPreset ?? this.cyclesPreset,
      soundFontFilename: clearSoundFont ? null : (soundFontFilename ?? this.soundFontFilename),
    );
  }
}

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kCatalogUrl = 'catalog_url';
  static const _kBinBaseUrl = 'bin_base_url';
  static const _kCoverBaseUrl = 'cover_base_url';
  static const _kLinearFilter = 'linear_filter';
  static const _kCyclesPreset = 'cycles_preset';
  static const _kSoundFont = 'soundfont_filename';

  Directory? _rootDir;

  Future<Directory> getRootDir() async {
    if (_rootDir != null) return _rootDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'dosbox_cn'));
    await dir.create(recursive: true);
    _rootDir = dir;
    return dir;
  }

  Future<Directory> getGamesDir() async {
    final dir = Directory(p.join((await getRootDir()).path, 'games'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> getSavesDir() async {
    final dir = Directory(p.join((await getRootDir()).path, 'saves'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> getStatesDir(String gameId) async {
    final safeId = _sanitizeFilename(gameId);
    final dir = Directory(p.join((await getRootDir()).path, 'states', safeId));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> getSystemDir() async {
    final dir = Directory(p.join((await getRootDir()).path, 'system'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> getCatalogCacheFile() async {
    final dir = Directory(p.join((await getRootDir()).path, 'cache'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'games.json'));
  }

  Future<File> getGameZipFile(String identifier) async {
    final gamesDir = await getGamesDir();
    return File(p.join(gamesDir.path, '${_sanitizeFilename(identifier)}.zip'));
  }

  Future<bool> isGameDownloaded(String identifier) async {
    final file = await getGameZipFile(identifier);
    return file.exists();
  }

  Future<Set<String>> listDownloadedGameIds() async {
    final gamesDir = await getGamesDir();
    final ids = <String>{};
    await for (final entity in gamesDir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.zip')) {
        ids.add(p.basenameWithoutExtension(entity.path));
      }
    }
    return ids;
  }

  Future<void> deleteGameZip(String identifier) async {
    final file = await getGameZipFile(identifier);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> getStateSlotFile(String gameId, int slot) async {
    final dir = await getStatesDir(gameId);
    return File(p.join(dir.path, 'slot_$slot.state'));
  }

  Future<void> writeStateSlot(String gameId, int slot, Uint8List data) async {
    final file = await getStateSlotFile(gameId, slot);
    await file.writeAsBytes(data, flush: true);
  }

  Future<Uint8List?> readStateSlot(String gameId, int slot) async {
    final file = await getStateSlotFile(gameId, slot);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<List<int>> listExistingStateSlots(String gameId) async {
    final slots = <int>[];
    for (var i = 1; i <= 4; i++) {
      final f = await getStateSlotFile(gameId, i);
      if (await f.exists()) slots.add(i);
    }
    return slots;
  }

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      catalogUrl: prefs.getString(_kCatalogUrl) ?? AppSettings.defaultCatalogUrl,
      binBaseUrl: prefs.getString(_kBinBaseUrl) ?? AppSettings.defaultBinBaseUrl,
      coverBaseUrl: prefs.getString(_kCoverBaseUrl) ?? AppSettings.defaultCoverBaseUrl,
      linearFilter: prefs.getBool(_kLinearFilter) ?? false,
      cyclesPreset: prefs.getString(_kCyclesPreset) ?? 'auto',
      soundFontFilename: prefs.getString(_kSoundFont),
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCatalogUrl, settings.catalogUrl);
    await prefs.setString(_kBinBaseUrl, settings.binBaseUrl);
    await prefs.setString(_kCoverBaseUrl, settings.coverBaseUrl);
    await prefs.setBool(_kLinearFilter, settings.linearFilter);
    await prefs.setString(_kCyclesPreset, settings.cyclesPreset);
    if (settings.soundFontFilename != null && settings.soundFontFilename!.isNotEmpty) {
      await prefs.setString(_kSoundFont, settings.soundFontFilename!);
    } else {
      await prefs.remove(_kSoundFont);
    }
  }

  Future<String> importSoundFont(File sourceFile) async {
    final sysDir = await getSystemDir();
    final filename = p.basename(sourceFile.path);
    final dest = File(p.join(sysDir.path, filename));
    await sourceFile.copy(dest.path);
    return filename;
  }

  /// Writes a `<basename>.conf` next to `<basename>.zip` so DOSBox-Pure (`dosbox_pure_conf = outside`)
  /// automatically runs the verified `executable` from games.json without manual menu selection.
  Future<File> writeAutoStartConf(File zipFile, String executable) async {
    final dir = zipFile.parent.path;
    final baseName = p.basenameWithoutExtension(zipFile.path);
    final confFile = File(p.join(dir, '$baseName.conf'));

    final normalized = executable.trim().replaceAll('/', '\\');
    final lastSlash = normalized.lastIndexOf('\\');
    final lines = <String>[
      '[autoexec]',
      '@echo off',
      'C:',
      r'cd \',
    ];
    if (lastSlash > 0) {
      final subDir = normalized.substring(0, lastSlash);
      final exeName = normalized.substring(lastSlash + 1);
      lines.add('cd $subDir');
      lines.add(exeName);
    } else {
      lines.add(normalized);
    }

    await confFile.writeAsString('${lines.join('\r\n')}\r\n', flush: true);
    return confFile;
  }

  String _sanitizeFilename(String raw) {
    return raw.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  }
}
