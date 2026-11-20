import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Standard Libretro keyboard codes (subset matching libretro.h enum retro_key).
class RetroKey {
  RetroKey._();

  static const int backspace = 8;
  static const int tab = 9;
  static const int enter = 13;
  static const int escape = 27;
  static const int space = 32;

  static const int key0 = 48;
  static const int key1 = 49;
  static const int key2 = 50;
  static const int key3 = 51;
  static const int key4 = 52;
  static const int key5 = 53;
  static const int key6 = 54;
  static const int key7 = 55;
  static const int key8 = 56;
  static const int key9 = 57;

  static const int a = 97;
  static const int b = 98;
  static const int c = 99;
  static const int d = 100;
  static const int e = 101;
  static const int f = 102;
  static const int g = 103;
  static const int h = 104;
  static const int i = 105;
  static const int j = 106;
  static const int k = 107;
  static const int l = 108;
  static const int m = 109;
  static const int n = 110;
  static const int o = 111;
  static const int p = 112;
  static const int q = 113;
  static const int r = 114;
  static const int s = 115;
  static const int t = 116;
  static const int u = 117;
  static const int v = 118;
  static const int w = 119;
  static const int x = 120;
  static const int y = 121;
  static const int z = 122;

  static const int up = 273;
  static const int down = 274;
  static const int right = 275;
  static const int left = 276;

  static const int f1 = 282;
  static const int f2 = 283;
  static const int f3 = 284;
  static const int f4 = 285;
  static const int f5 = 286;
  static const int f6 = 287;
  static const int f7 = 288;
  static const int f8 = 289;
  static const int f9 = 290;
  static const int f10 = 291;
  static const int f11 = 292;
  static const int f12 = 293;

  static const int rShift = 303;
  static const int lShift = 304;
  static const int rCtrl = 305;
  static const int lCtrl = 306;
  static const int rAlt = 307;
  static const int lAlt = 308;

  /// Maps a single ASCII character to its Libretro keycode, or null if unsupported.
  static int? fromAsciiChar(String ch) {
    if (ch.isEmpty) return null;
    final code = ch.toLowerCase().codeUnitAt(0);
    if ((code >= 97 && code <= 122) || (code >= 48 && code <= 57)) {
      return code;
    }
    if (ch == ' ') return space;
    if (ch == '\n') return enter;
    return null;
  }
}

enum MouseButton { left, right, middle }

/// Standard Libretro joypad button IDs.
class JoypadButton {
  JoypadButton._();

  static const int b = 0;
  static const int y = 1;
  static const int select = 2;
  static const int start = 3;
  static const int up = 4;
  static const int down = 5;
  static const int left = 6;
  static const int right = 7;
  static const int a = 8;
  static const int x = 9;
  static const int l = 10;
  static const int r = 11;
  static const int l2 = 12;
  static const int r2 = 13;
  static const int l3 = 14;
  static const int r3 = 15;
}

class DosboxStartResult {
  const DosboxStartResult({
    required this.textureId,
    required this.aspectRatio,
  });

  final int textureId;
  final double aspectRatio;
}

/// Unified Flutter interface to the native C++ Libretro host running DOSBox-Pure.
class DosboxEngine {
  static const MethodChannel _channel = MethodChannel('com.gs.dosbox_engine');

  Future<DosboxStartResult> startGame({
    required String gamePath,
    required String saveDir,
    required String systemDir,
    bool linearFilter = false,
    Map<String, String> coreOptions = const {},
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('startGame', {
      'gamePath': gamePath,
      'saveDir': saveDir,
      'systemDir': systemDir,
      'linearFilter': linearFilter,
      'coreOptions': coreOptions,
    });
    if (result == null || result['textureId'] == null) {
      throw PlatformException(
        code: 'START_FAILED',
        message: 'Native DOSBox engine did not return a valid textureId.',
      );
    }
    return DosboxStartResult(
      textureId: (result['textureId'] as num).toInt(),
      aspectRatio: (result['aspectRatio'] as num?)?.toDouble() ?? (4.0 / 3.0),
    );
  }

  Future<void> pause() => _channel.invokeMethod<void>('pause');

  Future<void> resume() => _channel.invokeMethod<void>('resume');

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<void> reset() => _channel.invokeMethod<void>('reset');

  Future<void> setFastForward(int multiplier) =>
      _channel.invokeMethod<void>('setFastForward', {'multiplier': multiplier});

  Future<void> setLinearFilter(bool enabled) =>
      _channel.invokeMethod<void>('setLinearFilter', {'enabled': enabled});

  Future<void> updateCoreOption(String key, String value) =>
      _channel.invokeMethod<void>('updateCoreOption', {'key': key, 'value': value});

  void sendKeyEvent(int retroKey, bool down) {
    _channel.invokeMethod<void>('sendKeyEvent', {
      'key': retroKey,
      'down': down,
    });
  }

  void sendMouseDelta(int dx, int dy) {
    _channel.invokeMethod<void>('sendMouseDelta', {'dx': dx, 'dy': dy});
  }

  void sendMouseButton(MouseButton button, bool down) {
    _channel.invokeMethod<void>('sendMouseButton', {
      'button': button.index,
      'down': down,
    });
  }

  /// Sends normalized pointer coordinates in [-1.0, 1.0] range.
  void sendPointer(double normX, double normY, bool pressed) {
    final int x = (normX.clamp(-1.0, 1.0) * 0x7fff).round();
    final int y = (normY.clamp(-1.0, 1.0) * 0x7fff).round();
    _channel.invokeMethod<void>('sendPointer', {
      'x': x,
      'y': y,
      'pressed': pressed,
    });
  }

  void sendJoypadButton(int retroId, bool down) {
    _channel.invokeMethod<void>('sendJoypadButton', {
      'id': retroId,
      'down': down,
    });
  }

  Future<Uint8List?> saveState() =>
      _channel.invokeMethod<Uint8List>('saveState');

  Future<bool> loadState(Uint8List data) async {
    final ok = await _channel.invokeMethod<bool>('loadState', {'data': data});
    return ok ?? false;
  }
}
