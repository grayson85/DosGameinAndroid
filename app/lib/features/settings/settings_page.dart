import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/storage_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _catalogCtrl;
  late TextEditingController _binCtrl;
  late TextEditingController _coverCtrl;

  static const _cyclesOptions = [
    ('auto', '自动（推荐，省电平衡）'),
    ('max', '最大性能（适合 486/3D 游戏）'),
    ('3000', '固定 3000（早期 286/386 老游戏防过快）'),
    ('10000', '固定 10000（中速 386）'),
    ('25000', '固定 25000（中速 486）'),
  ];

  @override
  void initState() {
    super.initState();
    _catalogCtrl = TextEditingController(text: widget.settings.catalogUrl);
    _binCtrl = TextEditingController(text: widget.settings.binBaseUrl);
    _coverCtrl = TextEditingController(text: widget.settings.coverBaseUrl);
  }

  @override
  void dispose() {
    _catalogCtrl.dispose();
    _binCtrl.dispose();
    _coverCtrl.dispose();
    super.dispose();
  }

  Future<void> _update(AppSettings next) async {
    await StorageService.instance.saveSettings(next);
    widget.onSettingsChanged(next);
  }

  Future<void> _importSoundFont() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sf2', 'sf3'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final filename = await StorageService.instance.importSoundFont(File(path));
    await _update(widget.settings.copyWith(soundFontFilename: filename));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 MIDI 音源：$filename')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('模拟器设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('画面与性能', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('线性平滑滤波'),
            subtitle: const Text('关闭为锐利复古像素点阵（推荐），开启为平滑柔化'),
            value: s.linearFilter,
            onChanged: (v) => _update(s.copyWith(linearFilter: v)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _cyclesOptions.any((o) => o.$1 == s.cyclesPreset) ? s.cyclesPreset : 'auto',
            decoration: const InputDecoration(
              labelText: 'DOS CPU 速度（Cycles）',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final (value, label) in _cyclesOptions)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (v) {
              if (v != null) _update(s.copyWith(cyclesPreset: v));
            },
          ),
          const Divider(height: 32),
          const Text('高品质 MIDI 音效',
              style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('SoundFont（.sf2）音源文件'),
            subtitle: Text(
              s.soundFontFilename != null
                  ? '当前已启用：${s.soundFontFilename}'
                  : '未配置（默认使用 AdLib/SoundBlaster；导入 .sf2 可大幅提升《仙剑》等 MIDI 配乐音质）',
            ),
            trailing: FilledButton.tonal(
              onPressed: _importSoundFont,
              child: const Text('导入 .sf2'),
            ),
          ),
          if (s.soundFontFilename != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _update(s.copyWith(clearSoundFont: true)),
                child: const Text('恢复默认音源'),
              ),
            ),
          const Divider(height: 32),
          const Text('游戏数据源配置',
              style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _catalogCtrl,
            decoration: const InputDecoration(
              labelText: 'games.json 目录地址',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _binCtrl,
            decoration: const InputDecoration(
              labelText: '游戏 .zip 下载源前缀',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _coverCtrl,
            decoration: const InputDecoration(
              labelText: '封面图片源前缀',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: () {
                  _update(
                    s.copyWith(
                      catalogUrl: _catalogCtrl.text.trim(),
                      binBaseUrl: _binCtrl.text.trim(),
                      coverBaseUrl: _coverCtrl.text.trim(),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('数据源设置已保存')),
                  );
                },
                child: const Text('保存数据源'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () {
                  _catalogCtrl.text = AppSettings.defaultCatalogUrl;
                  _binCtrl.text = AppSettings.defaultBinBaseUrl;
                  _coverCtrl.text = AppSettings.defaultCoverBaseUrl;
                  _update(
                    s.copyWith(
                      catalogUrl: AppSettings.defaultCatalogUrl,
                      binBaseUrl: AppSettings.defaultBinBaseUrl,
                      coverBaseUrl: AppSettings.defaultCoverBaseUrl,
                    ),
                  );
                },
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
