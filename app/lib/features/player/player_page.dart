import 'dart:io';

import 'package:dosbox_engine/dosbox_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/game_entry.dart';
import '../../services/storage_service.dart';
import '../controls/virtual_controls.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.game,
    required this.zipFile,
    required this.settings,
    this.cdromMode = false,
  });

  final GameEntry game;
  final File zipFile;
  final AppSettings settings;
  final bool cdromMode;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  final DosboxEngine _engine = DosboxEngine();
  final FocusNode _keyboardFocus = FocusNode();

  int? _textureId;
  double _aspectRatio = 4.0 / 3.0;
  String? _error;
  bool _loading = true;
  String _statusText = '准备启动 DOSBox-Pure...';

  late ControlMode _controlMode;
  int _fastForward = 1;
  bool _showKeyboard = false;
  bool _showHud = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controlMode = widget.game.defaultControlMode;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootGame();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.stop();
    _keyboardFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_textureId == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _engine.pause();
    } else if (state == AppLifecycleState.resumed) {
      _engine.resume();
    }
  }

  bool _manualStartMenu = false;

  Future<void> _bootGame() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _textureId = null;
        _statusText = '1/3 准备存档与系统目录...';
      });
    }
    try {
      final storage = StorageService.instance;
      final saveDir = await storage.getSavesDir();
      final systemDir = await storage.getSystemDir();

      final useAutoConf = !_manualStartMenu && widget.game.executable.isNotEmpty;
      if (useAutoConf) {
        if (mounted) setState(() => _statusText = '2/3 生成启动配置...');
        await storage.writeAutoStartConf(
          widget.zipFile,
          widget.game.executable,
          cdromMode: widget.cdromMode,
        );
      }

      final options = <String, String>{
        'dosbox_pure_cycles': widget.settings.cyclesPreset,
        'dosbox_pure_mouse_input':
            _controlMode == ControlMode.directMouse ? 'direct' : 'virtual',
        'dosbox_pure_aspect_correction': 'true',
        'dosbox_pure_conf': useAutoConf ? 'outside' : 'false',
      };
      if (widget.settings.soundFontFilename != null &&
          widget.settings.soundFontFilename!.isNotEmpty) {
        options['dosbox_pure_midi'] = widget.settings.soundFontFilename!;
      }

      final launchPath =
          widget.cdromMode ? '${widget.zipFile.path}#D' : widget.zipFile.path;

      if (mounted) {
        setState(() => _statusText = widget.cdromMode
            ? '3/3 以 D: 光驱模式加载核心...'
            : '3/3 正在加载 DOSBox-Pure 核心...');
      }

      final startResult = await _engine
          .startGame(
            gamePath: launchPath,
            saveDir: saveDir.path,
            systemDir: systemDir.path,
            linearFilter: widget.settings.linearFilter,
            coreOptions: options,
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw Exception('启动核心超时（12秒），请返回重试或切换手动启动菜单'),
          );

      if (!mounted) return;
      setState(() {
        _textureId = startResult.textureId;
        _aspectRatio = startResult.aspectRatio > 0.5 ? startResult.aspectRatio : (4.0 / 3.0);
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

  void _cycleControlMode() {
    const values = ControlMode.values;
    final next = values[(_controlMode.index + 1) % values.length];
    setState(() => _controlMode = next);
    _engine.updateCoreOption(
      'dosbox_pure_mouse_input',
      next == ControlMode.directMouse ? 'direct' : 'virtual',
    );
  }

  void _cycleFastForward() {
    final next = _fastForward == 1 ? 2 : (_fastForward == 2 ? 4 : 1);
    setState(() => _fastForward = next);
    _engine.setFastForward(next);
  }

  void _handleHardwareKey(KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final up = event is KeyUpEvent;
    if (!down && !up) return;
    final retro = _mapLogicalKey(event.logicalKey);
    if (retro != null) {
      _engine.sendKeyEvent(retro, down);
    }
  }

  int? _mapLogicalKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return RetroKey.up;
    if (key == LogicalKeyboardKey.arrowDown) return RetroKey.down;
    if (key == LogicalKeyboardKey.arrowLeft) return RetroKey.left;
    if (key == LogicalKeyboardKey.arrowRight) return RetroKey.right;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      return RetroKey.enter;
    }
    if (key == LogicalKeyboardKey.space) return RetroKey.space;
    if (key == LogicalKeyboardKey.escape) return RetroKey.escape;
    if (key == LogicalKeyboardKey.backspace) return RetroKey.backspace;
    if (key == LogicalKeyboardKey.tab) return RetroKey.tab;
    if (key == LogicalKeyboardKey.altLeft) return RetroKey.lAlt;
    if (key == LogicalKeyboardKey.altRight) return RetroKey.rAlt;
    if (key == LogicalKeyboardKey.controlLeft) return RetroKey.lCtrl;
    if (key == LogicalKeyboardKey.controlRight) return RetroKey.rCtrl;
    if (key == LogicalKeyboardKey.shiftLeft) return RetroKey.lShift;
    if (key == LogicalKeyboardKey.shiftRight) return RetroKey.rShift;
    final label = key.keyLabel;
    if (label.length == 1) {
      return RetroKey.fromAsciiChar(label);
    }
    return null;
  }

  Future<void> _openSaveStateDialog() async {
    await _engine.pause();
    final existing = await StorageService.instance.listExistingStateSlots(widget.game.identifier);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1F29),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '即时存档（Save States）',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (var slot = 1; slot <= 4; slot++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '槽位 $slot ${existing.contains(slot) ? "（已有存档）" : "（空）"}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonal(
                          onPressed: () async {
                            final data = await _engine.saveState();
                            if (data != null) {
                              await StorageService.instance
                                  .writeStateSlot(widget.game.identifier, slot, data);
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                _showSnack('已保存至槽位 $slot');
                              }
                            } else {
                              _showSnack('当前核心状态暂不支持保存');
                            }
                          },
                          child: const Text('存'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: existing.contains(slot)
                              ? () async {
                                  final data = await StorageService.instance
                                      .readStateSlot(widget.game.identifier, slot);
                                  if (data != null) {
                                    final ok = await _engine.loadState(data);
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      _showSnack(ok ? '已读取槽位 $slot' : '读档失败');
                                    }
                                  }
                                }
                              : null,
                          child: const Text('读'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    await _engine.resume();
  }

  void _openHelpSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1F29),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.game.displayName} · 信息',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (widget.game.executable.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('自动启动程序：${widget.game.executable}',
                      style: const TextStyle(color: Colors.cyanAccent)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: Text(_manualStartMenu ? '改回自动启动 (${widget.game.executable})' : '改为手动选文件启动（打开 DOSBox 菜单）'),
                    onPressed: () {
                      Navigator.pop(context);
                      _manualStartMenu = !_manualStartMenu;
                      _bootGame();
                    },
                  ),
                ],
                if (widget.game.keymaps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('按键说明', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  for (final entry in widget.game.keymaps.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${entry.key}：${entry.value}',
                          style: const TextStyle(color: Colors.white)),
                    ),
                ],
                if (widget.game.cheats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('秘籍', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  for (final entry in widget.game.cheats.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${entry.key} → ${entry.value}',
                          style: const TextStyle(color: Colors.white)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _handleHardwareKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // 4:3 DOS screen
              Center(
                child: _buildScreen(),
              ),

              // Active touch controls overlay
              if (_textureId != null && !_showKeyboard)
                Positioned.fill(
                  child: switch (_controlMode) {
                    ControlMode.joystick => Align(
                        alignment: Alignment.bottomCenter,
                        child: RpgPadOverlay(engine: _engine, useJoystick: true),
                      ),
                    ControlMode.rpgPad => Align(
                        alignment: Alignment.bottomCenter,
                        child: RpgPadOverlay(engine: _engine, useJoystick: false),
                      ),
                    ControlMode.touchpadMouse => TouchpadMouseOverlay(engine: _engine),
                    ControlMode.directMouse => Center(
                        child: AspectRatio(
                          aspectRatio: _aspectRatio,
                          child: DirectMouseOverlay(engine: _engine),
                        ),
                      ),
                  },
                ),

              // Top compact HUD toolbar
              if (_showHud)
                Positioned(
                  top: 6,
                  left: 8,
                  right: 8,
                  child: _buildTopToolbar(),
                )
              else
                Positioned(
                  top: 6,
                  right: 8,
                  child: IconButton.filledTonal(
                    onPressed: () => setState(() => _showHud = true),
                    icon: const Icon(Icons.tune, size: 18),
                  ),
                ),

              // Floating compact PC keyboard
              if (_showKeyboard)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: CompactKeyboardPanel(
                    engine: _engine,
                    onClose: () => setState(() => _showKeyboard = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreen() {
    if (_loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_statusText, style: const TextStyle(color: Colors.white70)),
        ],
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回游戏库'),
            ),
          ],
        ),
      );
    }
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: Texture(textureId: _textureId!),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              tooltip: '退出游戏',
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            Text(
              widget.game.displayName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            ActionChip(
              label: Text(_controlMode.label, style: const TextStyle(fontSize: 12)),
              onPressed: _cycleControlMode,
            ),
            const SizedBox(width: 6),
            ActionChip(
              label: Text('${_fastForward}x', style: const TextStyle(fontSize: 12)),
              onPressed: _cycleFastForward,
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '即时存档',
              icon: const Icon(Icons.save, color: Colors.white, size: 20),
              onPressed: _openSaveStateDialog,
            ),
            IconButton(
              tooltip: 'PC 虚拟键盘',
              icon: Icon(
                Icons.keyboard,
                color: _showKeyboard ? Colors.cyanAccent : Colors.white,
                size: 20,
              ),
              onPressed: () => setState(() => _showKeyboard = !_showKeyboard),
            ),
            IconButton(
              tooltip: '重启游戏',
              icon: const Icon(Icons.restart_alt, color: Colors.white, size: 20),
              onPressed: () {
                _engine.reset();
                _showSnack('已重启游戏');
              },
            ),
            IconButton(
              tooltip: '启动项与秘籍',
              icon: const Icon(Icons.info_outline, color: Colors.white, size: 20),
              onPressed: _openHelpSheet,
            ),
            IconButton(
              tooltip: '隐藏工具栏',
              icon: const Icon(Icons.visibility_off, color: Colors.white70, size: 18),
              onPressed: () => setState(() => _showHud = false),
            ),
          ],
        ),
      ),
    );
  }
}
