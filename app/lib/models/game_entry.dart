import 'dart:convert';

enum ControlMode {
  joystick,
  rpgPad,
  touchpadMouse,
  directMouse,
}

extension ControlModeLabel on ControlMode {
  String get label {
    switch (this) {
      case ControlMode.joystick:
        return '摇杆/键盘';
      case ControlMode.rpgPad:
        return '十字键/键盘';
      case ControlMode.touchpadMouse:
        return '触控板鼠标';
      case ControlMode.directMouse:
        return '直触鼠标';
    }
  }
}

class GameEntry {
  const GameEntry({
    required this.identifier,
    required this.nameZhHans,
    required this.nameZhHant,
    required this.nameEn,
    required this.executable,
    this.releaseYear,
    this.type,
    this.coverFilename,
    this.sha256,
    this.filesize,
    this.keymaps = const {},
    this.cheats = const {},
    this.links = const {},
    this.isLocalImport = false,
  });

  final String identifier;
  final String nameZhHans;
  final String nameZhHant;
  final String nameEn;
  final int? releaseYear;
  final String? type;
  final String executable;
  final String? coverFilename;
  final String? sha256;
  final int? filesize;
  final Map<String, String> keymaps;
  final Map<String, String> cheats;
  final Map<String, String> links;
  final bool isLocalImport;

  String get displayName =>
      nameZhHans.isNotEmpty ? nameZhHans : (nameZhHant.isNotEmpty ? nameZhHant : identifier);

  String get subtitle {
    final parts = <String>[];
    if (releaseYear != null) parts.add('$releaseYear');
    if (type != null && type!.isNotEmpty) parts.add(type!);
    if (filesize != null && filesize! > 0) parts.add(formattedSize);
    return parts.join(' · ');
  }

  String get formattedSize {
    final bytes = filesize ?? 0;
    if (bytes <= 0) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  /// Selects the most ergonomic default touch preset based on game genre.
  ControlMode get defaultControlMode {
    switch (type?.toUpperCase()) {
      case 'SIM':
      case 'SLG':
      case 'RTS':
      case 'AVG':
      case 'PUZ':
      case 'HGA':
        return ControlMode.touchpadMouse;
      case 'RPG':
      case 'ACT':
      case 'SPG':
      default:
        return ControlMode.joystick;
    }
  }

  String? coverUrl(String coverBaseUrl) {
    if (isLocalImport || coverFilename == null || coverFilename!.isEmpty) {
      return null;
    }
    final base = coverBaseUrl.endsWith('/') ? coverBaseUrl : '$coverBaseUrl/';
    return '$base${Uri.encodeComponent(identifier)}/${Uri.encodeComponent(coverFilename!)}';
  }

  String downloadUrl(String binBaseUrl) {
    final base = binBaseUrl.endsWith('/') ? binBaseUrl : '$binBaseUrl/';
    return '$base${Uri.encodeComponent(identifier)}.zip';
  }

  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return identifier.toLowerCase().contains(q) ||
        nameZhHans.toLowerCase().contains(q) ||
        nameZhHant.toLowerCase().contains(q) ||
        nameEn.toLowerCase().contains(q);
  }

  factory GameEntry.fromJson(String key, Map<String, dynamic> json) {
    final nameMap = (json['name'] is Map)
        ? Map<String, dynamic>.from(json['name'] as Map)
        : <String, dynamic>{};

    Map<String, String> parseStringMap(dynamic raw) {
      if (raw is! Map) return const {};
      final result = <String, String>{};
      raw.forEach((k, v) {
        if (k != null && v != null) {
          result[k.toString()] = v.toString();
        }
      });
      return result;
    }

    return GameEntry(
      identifier: (json['identifier'] as String?) ?? key,
      nameZhHans: (nameMap['zh-Hans'] as String?) ?? key,
      nameZhHant: (nameMap['zh-Hant'] as String?) ?? '',
      nameEn: (nameMap['en'] as String?) ?? '',
      releaseYear: (json['releaseYear'] as num?)?.toInt(),
      type: json['type'] as String?,
      executable: (json['executable'] as String?) ?? '',
      coverFilename: json['coverFilename'] as String?,
      sha256: json['sha256'] as String?,
      filesize: (json['filesize'] as num?)?.toInt(),
      keymaps: parseStringMap(json['keymaps']),
      cheats: parseStringMap(json['cheats']),
      links: parseStringMap(json['links']),
    );
  }

  factory GameEntry.localImport({
    required String identifier,
    required int filesize,
  }) {
    return GameEntry(
      identifier: identifier,
      nameZhHans: identifier,
      nameZhHant: '',
      nameEn: '',
      executable: '',
      type: 'LOCAL',
      filesize: filesize,
      isLocalImport: true,
    );
  }

  static List<GameEntry> parseCatalogJson(String jsonSource) {
    final decoded = jsonDecode(jsonSource);
    if (decoded is! Map<String, dynamic> || decoded['games'] is! Map) {
      throw const FormatException('Invalid games.json structure: missing "games" map.');
    }
    final gamesMap = decoded['games'] as Map<String, dynamic>;
    final list = <GameEntry>[];
    gamesMap.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        list.add(GameEntry.fromJson(key, value));
      }
    });
    return list;
  }
}
