import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/game_entry.dart';
import '../../services/catalog_service.dart';
import '../../services/download_service.dart';
import '../../services/storage_service.dart';
import '../player/player_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.settings,
  });

  final AppSettings settings;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final CatalogService _catalogService = CatalogService();
  final DownloadService _downloadService = DownloadService();
  final TextEditingController _searchController = TextEditingController();

  List<GameEntry> _catalog = [];
  List<GameEntry> _localImports = [];
  Set<String> _downloadedIds = {};
  final Map<String, double> _downloadProgress = {};

  String _selectedFilter = '全部';
  String _query = '';
  bool _loading = true;
  String? _error;

  static const _filters = [
    '全部',
    '已下载',
    'RPG',
    'ACT',
    'SIM',
    'SLG',
    'AVG',
    'PUZ',
    'RTS',
    'SPG',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final downloaded = await StorageService.instance.listDownloadedGameIds();
      List<GameEntry> games = [];
      try {
        games = await _catalogService.loadCatalog(
          catalogUrl: widget.settings.catalogUrl,
          forceRefresh: forceRefresh,
        );
      } catch (e) {
        _error = e.toString();
      }

      final catalogIds = games.map((g) => g.identifier).toSet();
      final localOnly = <GameEntry>[];
      for (final id in downloaded) {
        if (!catalogIds.contains(id)) {
          final f = await StorageService.instance.getGameZipFile(id);
          final size = await f.length();
          localOnly.add(GameEntry.localImport(identifier: id, filesize: size));
        }
      }

      if (!mounted) return;
      setState(() {
        _catalog = games;
        _localImports = localOnly;
        _downloadedIds = downloaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<GameEntry> get _filteredGames {
    final all = [..._localImports, ..._catalog];
    return all.where((game) {
      if (!game.matchesQuery(_query)) return false;
      if (_selectedFilter == '全部') return true;
      if (_selectedFilter == '已下载') {
        return _downloadedIds.contains(game.identifier);
      }
      return game.type?.toUpperCase() == _selectedFilter;
    }).toList();
  }

  Future<void> _importLocalZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'dosz'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    try {
      final entry = await _downloadService.importLocalZip(File(path));
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入本地游戏：${entry.displayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    }
  }

  Future<void> _downloadGame(GameEntry game) async {
    if (_downloadProgress.containsKey(game.identifier)) return;
    setState(() => _downloadProgress[game.identifier] = 0.01);
    try {
      await _downloadService.downloadGame(
        game: game,
        binBaseUrl: widget.settings.binBaseUrl,
        onProgress: (p) {
          if (mounted) {
            setState(() => _downloadProgress[game.identifier] = p);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(game.identifier);
        _downloadedIds.add(game.identifier);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${game.displayName} 下载并校验完成')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadProgress.remove(game.identifier));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    }
  }

  Future<void> _launchGame(GameEntry game, {bool cdromMode = false}) async {
    final file = await StorageService.instance.getGameZipFile(game.identifier);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先下载或导入该游戏包')),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          game: game,
          zipFile: file,
          settings: widget.settings,
          cdromMode: cdromMode,
        ),
      ),
    );
  }

  void _openGameDetail(GameEntry game) {
    final downloaded = _downloadedIds.contains(game.identifier);
    final cover = game.coverUrl(widget.settings.coverBaseUrl);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F29),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 96,
                          height: 72,
                          child: cover != null
                              ? Image.network(
                                  cover,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _placeholderCover(),
                                )
                              : _placeholderCover(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              game.displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (game.nameEn.isNotEmpty)
                              Text(game.nameEn,
                                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            const SizedBox(height: 6),
                            Text(
                              game.subtitle,
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 13),
                            ),
                            if (game.executable.isNotEmpty)
                              Text(
                                '启动程序：${game.executable}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: Icon(downloaded ? Icons.play_arrow : Icons.download),
                          label: Text(downloaded ? '立即开始游戏' : '下载游戏包 (${game.formattedSize})'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (downloaded) {
                              _launchGame(game);
                            } else {
                              _downloadGame(game);
                            }
                          },
                        ),
                      ),
                      if (downloaded) ...[
                        const SizedBox(width: 10),
                        IconButton.outlined(
                          tooltip: '删除本地游戏包',
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () async {
                            await StorageService.instance.deleteGameZip(game.identifier);
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadData();
                          },
                        ),
                      ],
                    ],
                  ),
                  if (downloaded) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.album, size: 18),
                        label: const Text('光驱模式启动（D: 虚拟光驱，解决三国志5等光盘检测）'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _launchGame(game, cdromMode: true);
                        },
                      ),
                    ),
                  ],
                  if (game.keymaps.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('按键说明',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    for (final e in game.keymaps.entries)
                      Text('${e.key}：${e.value}', style: const TextStyle(color: Colors.white)),
                  ],
                  if (game.cheats.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('经典秘籍',
                        style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    for (final e in game.cheats.entries)
                      Text('${e.key} → ${e.value}', style: const TextStyle(color: Colors.white)),
                  ],
                  if (game.links.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('攻略与资料',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final e in game.links.entries)
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(e.value),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(e.key),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholderCover() {
    return Container(
      color: const Color(0xFF252C3A),
      alignment: Alignment.center,
      child: const Icon(Icons.videogame_asset, color: Colors.white38, size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = _filteredGames;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 900 ? 4 : (width >= 600 ? 3 : 2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('华语 DOS 怀旧盒'),
        actions: [
          IconButton(
            tooltip: '导入本地 .zip 游戏',
            icon: const Icon(Icons.folder_open),
            onPressed: _importLocalZip,
          ),
          IconButton(
            tooltip: '刷新游戏目录',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索 1898 款经典华语 DOS 游戏（如 仙剑 / 大富翁）',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, idx) {
                final f = _filters[idx];
                return ChoiceChip(
                  label: Text(f),
                  selected: _selectedFilter == f,
                  onSelected: (_) => setState(() => _selectedFilter = f),
                );
              },
            ),
          ),
          if (_error != null && _catalog.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '在线目录暂不可用（可点击右上角导入本地 .zip 游戏）：$_error',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : games.isEmpty
                    ? const Center(child: Text('没有匹配的游戏'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: games.length,
                        itemBuilder: (_, idx) => _buildGameCard(games[idx]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(GameEntry game) {
    final downloaded = _downloadedIds.contains(game.identifier);
    final progress = _downloadProgress[game.identifier];
    final cover = game.coverUrl(widget.settings.coverBaseUrl);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openGameDetail(game),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover != null
                      ? Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderCover(),
                        )
                      : _placeholderCover(),
                  if (downloaded)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('可玩',
                            style: TextStyle(fontSize: 10, color: Colors.white)),
                      ),
                    ),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(value: progress),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    game.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
