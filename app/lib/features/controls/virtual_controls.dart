import 'dart:async';
import 'dart:math' as math;

import 'package:dosbox_engine/dosbox_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Low-latency virtual button using raw [Listener] to avoid GestureDetector tap delay.
class RetroActionButton extends StatefulWidget {
  const RetroActionButton({
    super.key,
    required this.label,
    required this.onChanged,
    this.size = 56,
    this.color = const Color(0xAA263238),
    this.pressedColor = const Color(0xDD00ACC1),
    this.borderRadius = 28,
  });

  final String label;
  final ValueChanged<bool> onChanged;
  final double size;
  final Color color;
  final Color pressedColor;
  final double borderRadius;

  @override
  State<RetroActionButton> createState() => _RetroActionButtonState();
}

class _RetroActionButtonState extends State<RetroActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 40),
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _pressed ? widget.pressedColor : widget.color,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _pressed ? Colors.cyanAccent : Colors.white30,
            width: 1.5,
          ),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Sliding 8-way D-pad that maps directly to DOS arrow keys with zero dead-tap latency.
class SlidingDPad extends StatefulWidget {
  const SlidingDPad({
    super.key,
    required this.engine,
    this.size = 152,
  });

  final DosboxEngine engine;
  final double size;

  @override
  State<SlidingDPad> createState() => _SlidingDPadState();
}

class _SlidingDPadState extends State<SlidingDPad> {
  bool _up = false;
  bool _down = false;
  bool _left = false;
  bool _right = false;

  void _updateDirection(Offset localPos) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = localPos - center;
    final deadzone = widget.size * 0.14;

    final nextUp = delta.dy < -deadzone;
    final nextDown = delta.dy > deadzone;
    final nextLeft = delta.dx < -deadzone;
    final nextRight = delta.dx > deadzone;

    _applyKey(RetroKey.up, nextUp, _up);
    _applyKey(RetroKey.down, nextDown, _down);
    _applyKey(RetroKey.left, nextLeft, _left);
    _applyKey(RetroKey.right, nextRight, _right);

    if (nextUp != _up || nextDown != _down || nextLeft != _left || nextRight != _right) {
      setState(() {
        _up = nextUp;
        _down = nextDown;
        _left = nextLeft;
        _right = nextRight;
      });
    }
  }

  void _releaseAll() {
    _applyKey(RetroKey.up, false, _up);
    _applyKey(RetroKey.down, false, _down);
    _applyKey(RetroKey.left, false, _left);
    _applyKey(RetroKey.right, false, _right);
    if (_up || _down || _left || _right) {
      setState(() {
        _up = false;
        _down = false;
        _left = false;
        _right = false;
      });
    }
  }

  void _applyKey(int key, bool next, bool prev) {
    if (next != prev) {
      widget.engine.sendKeyEvent(key, next);
    }
  }

  @override
  void dispose() {
    _releaseAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arm = widget.size * 0.34;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _updateDirection(e.localPosition),
      onPointerMove: (e) => _updateDirection(e.localPosition),
      onPointerUp: (_) => _releaseAll(),
      onPointerCancel: (_) => _releaseAll(),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black38,
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
            ),
            // Up
            Positioned(
              top: 6,
              child: _DPadSegment(width: arm, height: arm, active: _up, icon: Icons.arrow_drop_up),
            ),
            // Down
            Positioned(
              bottom: 6,
              child: _DPadSegment(width: arm, height: arm, active: _down, icon: Icons.arrow_drop_down),
            ),
            // Left
            Positioned(
              left: 6,
              child: _DPadSegment(width: arm, height: arm, active: _left, icon: Icons.arrow_left),
            ),
            // Right
            Positioned(
              right: 6,
              child: _DPadSegment(width: arm, height: arm, active: _right, icon: Icons.arrow_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _DPadSegment extends StatelessWidget {
  const _DPadSegment({
    required this.width,
    required this.height,
    required this.active,
    required this.icon,
  });

  final double width;
  final double height;
  final bool active;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: active ? const Color(0xCC00ACC1) : const Color(0x8837474F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? Colors.cyanAccent : Colors.white24),
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }
}

class JoystickDirections {
  const JoystickDirections({
    this.up = false,
    this.down = false,
    this.left = false,
    this.right = false,
  });

  static const neutral = JoystickDirections();

  final bool up;
  final bool down;
  final bool left;
  final bool right;

  bool get isNeutral => !up && !down && !left && !right;

  @override
  bool operator ==(Object other) =>
      other is JoystickDirections &&
      up == other.up &&
      down == other.down &&
      left == other.left &&
      right == other.right;

  @override
  int get hashCode => Object.hash(up, down, left, right);
}

/// Converts a joystick displacement vector into crisp 4-way cardinal + 8-way diagonal arrow states.
/// Cardinal sectors are slightly wider (±27°) so RPGs like Legend of Sword and Fairy feel steady.
JoystickDirections computeJoystickDirections(
  Offset delta, {
  required double deadzone,
}) {
  if (delta.distance < deadzone) {
    return JoystickDirections.neutral;
  }
  final angleDeg = math.atan2(delta.dy, delta.dx) * 180.0 / math.pi;
  if (angleDeg.abs() <= 27.0) {
    return const JoystickDirections(right: true);
  }
  if (angleDeg > 27.0 && angleDeg < 63.0) {
    return const JoystickDirections(down: true, right: true);
  }
  if (angleDeg >= 63.0 && angleDeg <= 117.0) {
    return const JoystickDirections(down: true);
  }
  if (angleDeg > 117.0 && angleDeg < 153.0) {
    return const JoystickDirections(down: true, left: true);
  }
  if (angleDeg.abs() >= 153.0) {
    return const JoystickDirections(left: true);
  }
  if (angleDeg > -153.0 && angleDeg < -117.0) {
    return const JoystickDirections(up: true, left: true);
  }
  if (angleDeg >= -117.0 && angleDeg <= -63.0) {
    return const JoystickDirections(up: true);
  }
  return const JoystickDirections(up: true, right: true);
}

/// Mobile-RPG style floating-anchor virtual thumbstick mapped to DOS arrow keys.
class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    required this.engine,
    this.touchZoneSize = 184,
    this.baseSize = 144,
    this.knobSize = 58,
  });

  final DosboxEngine engine;
  final double touchZoneSize;
  final double baseSize;
  final double knobSize;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  int? _activePointer;
  Offset? _anchor;
  Offset _knobOffset = Offset.zero;
  JoystickDirections _dirs = JoystickDirections.neutral;

  double get _maxTravel => (widget.baseSize - widget.knobSize) * 0.5 + 8.0;
  Offset get _restCenter => Offset(widget.touchZoneSize / 2, widget.touchZoneSize / 2);

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;

    final halfBase = widget.baseSize / 2;
    final minCoord = halfBase;
    final maxCoord = widget.touchZoneSize - halfBase;
    final clampedAnchor = Offset(
      event.localPosition.dx.clamp(minCoord, maxCoord),
      event.localPosition.dy.clamp(minCoord, maxCoord),
    );

    setState(() {
      _anchor = clampedAnchor;
      _knobOffset = Offset.zero;
    });
    _updateFromPosition(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _updateFromPosition(event.localPosition);
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _release();
  }

  void _updateFromPosition(Offset pos) {
    final anchor = _anchor ?? _restCenter;
    final rawDelta = pos - anchor;
    final dist = rawDelta.distance;
    final clampedOffset = dist > _maxTravel && dist > 0
        ? Offset(rawDelta.dx / dist * _maxTravel, rawDelta.dy / dist * _maxTravel)
        : rawDelta;

    final nextDirs = computeJoystickDirections(
      clampedOffset,
      deadzone: _maxTravel * 0.22,
    );

    if (_dirs.isNeutral && !nextDirs.isNeutral) {
      HapticFeedback.selectionClick();
    }
    _syncKeys(nextDirs);

    setState(() {
      _knobOffset = clampedOffset;
      _dirs = nextDirs;
    });
  }

  void _release() {
    _activePointer = null;
    _syncKeys(JoystickDirections.neutral);
    if (mounted) {
      setState(() {
        _anchor = null;
        _knobOffset = Offset.zero;
        _dirs = JoystickDirections.neutral;
      });
    }
  }

  void _syncKeys(JoystickDirections next) {
    if (next.up != _dirs.up) widget.engine.sendKeyEvent(RetroKey.up, next.up);
    if (next.down != _dirs.down) widget.engine.sendKeyEvent(RetroKey.down, next.down);
    if (next.left != _dirs.left) widget.engine.sendKeyEvent(RetroKey.left, next.left);
    if (next.right != _dirs.right) widget.engine.sendKeyEvent(RetroKey.right, next.right);
  }

  @override
  void dispose() {
    _syncKeys(JoystickDirections.neutral);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _anchor ?? _restCenter;
    final active = _activePointer != null;
    final baseLeft = center.dx - widget.baseSize / 2;
    final baseTop = center.dy - widget.baseSize / 2;
    final knobLeft = center.dx + _knobOffset.dx - widget.knobSize / 2;
    final knobTop = center.dy + _knobOffset.dy - widget.knobSize / 2;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: SizedBox(
        width: widget.touchZoneSize,
        height: widget.touchZoneSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Outer joystick base ring
            Positioned(
              left: baseLeft,
              top: baseTop,
              child: Container(
                width: widget.baseSize,
                height: widget.baseSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? const Color(0x661C2430) : const Color(0x441C2430),
                  border: Border.all(
                    color: active ? Colors.cyanAccent.withValues(alpha: 0.7) : Colors.white24,
                    width: 2,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 6,
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        size: 20,
                        color: _dirs.up ? Colors.cyanAccent : Colors.white30,
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: _dirs.down ? Colors.cyanAccent : Colors.white30,
                      ),
                    ),
                    Positioned(
                      left: 6,
                      child: Icon(
                        Icons.keyboard_arrow_left,
                        size: 20,
                        color: _dirs.left ? Colors.cyanAccent : Colors.white30,
                      ),
                    ),
                    Positioned(
                      right: 6,
                      child: Icon(
                        Icons.keyboard_arrow_right,
                        size: 20,
                        color: _dirs.right ? Colors.cyanAccent : Colors.white30,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Movable thumbstick knob
            Positioned(
              left: knobLeft,
              top: knobTop,
              child: Container(
                width: widget.knobSize,
                height: widget.knobSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: active
                        ? const [Color(0xEE26C6DA), Color(0xCC00838F)]
                        : const [Color(0xCC607D8B), Color(0xAA37474F)],
                  ),
                  border: Border.all(
                    color: active ? Colors.cyanAccent : Colors.white38,
                    width: 2,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// RPG / Action virtual gamepad overlay (Virtual Joystick or D-Pad + Enter/Space/Alt/Esc).
class RpgPadOverlay extends StatelessWidget {
  const RpgPadOverlay({
    super.key,
    required this.engine,
    this.useJoystick = true,
  });

  final DosboxEngine engine;
  final bool useJoystick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          useJoystick ? VirtualJoystick(engine: engine) : SlidingDPad(engine: engine),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RetroActionButton(
                    label: 'Esc',
                    size: 50,
                    onChanged: (d) => engine.sendKeyEvent(RetroKey.escape, d),
                  ),
                  const SizedBox(width: 14),
                  RetroActionButton(
                    label: 'Alt',
                    size: 50,
                    onChanged: (d) => engine.sendKeyEvent(RetroKey.lAlt, d),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RetroActionButton(
                    label: 'Space',
                    size: 62,
                    onChanged: (d) => engine.sendKeyEvent(RetroKey.space, d),
                  ),
                  const SizedBox(width: 14),
                  RetroActionButton(
                    label: 'Enter',
                    size: 62,
                    color: const Color(0xAA00695C),
                    onChanged: (d) => engine.sendKeyEvent(RetroKey.enter, d),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Touchpad-style relative mouse overlay (drag to move cursor, tap to click, dedicated L/R buttons).
class TouchpadMouseOverlay extends StatefulWidget {
  const TouchpadMouseOverlay({
    super.key,
    required this.engine,
    this.sensitivity = 1.6,
  });

  final DosboxEngine engine;
  final double sensitivity;

  @override
  State<TouchpadMouseOverlay> createState() => _TouchpadMouseOverlayState();
}

class _TouchpadMouseOverlayState extends State<TouchpadMouseOverlay> {
  final Map<int, Offset> _pointers = {};
  Offset? _downPos;
  DateTime? _downTime;
  double _accumX = 0;
  double _accumY = 0;

  void _triggerClick(MouseButton button) {
    widget.engine.sendMouseButton(button, true);
    Timer(const Duration(milliseconds: 60), () {
      widget.engine.sendMouseButton(button, false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              _pointers[e.pointer] = e.localPosition;
              if (_pointers.length == 1) {
                _downPos = e.localPosition;
                _downTime = DateTime.now();
              }
            },
            onPointerMove: (e) {
              final prev = _pointers[e.pointer];
              _pointers[e.pointer] = e.localPosition;
              if (prev != null && _pointers.length == 1) {
                _accumX += (e.localPosition.dx - prev.dx) * widget.sensitivity;
                _accumY += (e.localPosition.dy - prev.dy) * widget.sensitivity;
                final dx = _accumX.truncate();
                final dy = _accumY.truncate();
                if (dx != 0 || dy != 0) {
                  _accumX -= dx;
                  _accumY -= dy;
                  widget.engine.sendMouseDelta(dx, dy);
                }
              }
            },
            onPointerUp: (e) {
              final wasTwoFinger = _pointers.length == 2;
              _pointers.remove(e.pointer);
              if (_downTime != null && _downPos != null) {
                final elapsed = DateTime.now().difference(_downTime!).inMilliseconds;
                final dist = (e.localPosition - _downPos!).distance;
                if (elapsed < 220 && dist < 14) {
                  _triggerClick(wasTwoFinger ? MouseButton.right : MouseButton.left);
                }
              }
              if (_pointers.isEmpty) {
                _downPos = null;
                _downTime = null;
              }
            },
            onPointerCancel: (e) {
              _pointers.remove(e.pointer);
            },
          ),
        ),
        Positioned(
          left: 16,
          bottom: 16,
          child: Row(
            children: [
              RetroActionButton(
                label: '左键',
                size: 56,
                borderRadius: 14,
                color: const Color(0xAA00695C),
                onChanged: (d) => widget.engine.sendMouseButton(MouseButton.left, d),
              ),
              const SizedBox(width: 10),
              RetroActionButton(
                label: '右键',
                size: 56,
                borderRadius: 14,
                onChanged: (d) => widget.engine.sendMouseButton(MouseButton.right, d),
              ),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Row(
            children: [
              RetroActionButton(
                label: 'Esc',
                size: 50,
                borderRadius: 14,
                onChanged: (d) => widget.engine.sendKeyEvent(RetroKey.escape, d),
              ),
              const SizedBox(width: 10),
              RetroActionButton(
                label: 'Enter',
                size: 50,
                borderRadius: 14,
                onChanged: (d) => widget.engine.sendKeyEvent(RetroKey.enter, d),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Direct-touch absolute pointer overlay mapped to the game screen bounds.
class DirectMouseOverlay extends StatelessWidget {
  const DirectMouseOverlay({
    super.key,
    required this.engine,
  });

  final DosboxEngine engine;

  void _sendTouch(Offset localPos, Size size, bool pressed, {bool updateLeftButton = false}) {
    if (size.width <= 0 || size.height <= 0) return;
    final normX = (localPos.dx / size.width) * 2.0 - 1.0;
    final normY = (localPos.dy / size.height) * 2.0 - 1.0;
    engine.sendPointer(normX, normY, pressed);
    if (updateLeftButton) {
      engine.sendMouseButton(MouseButton.left, pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) =>
                    _sendTouch(e.localPosition, size, true, updateLeftButton: true),
                onPointerMove: (e) => _sendTouch(e.localPosition, size, true),
                onPointerUp: (e) =>
                    _sendTouch(e.localPosition, size, false, updateLeftButton: true),
                onPointerCancel: (e) =>
                    _sendTouch(e.localPosition, size, false, updateLeftButton: true),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Row(
                children: [
                  RetroActionButton(
                    label: '左键',
                    size: 52,
                    borderRadius: 14,
                    color: const Color(0xAA00695C),
                    onChanged: (d) => engine.sendMouseButton(MouseButton.left, d),
                  ),
                  const SizedBox(width: 10),
                  RetroActionButton(
                    label: '右键',
                    size: 52,
                    borderRadius: 14,
                    onChanged: (d) => engine.sendMouseButton(MouseButton.right, d),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Compact floating PC keyboard for entering cheats, save names, and F1-F12 shortcuts.
class CompactKeyboardPanel extends StatelessWidget {
  const CompactKeyboardPanel({
    super.key,
    required this.engine,
    required this.onClose,
  });

  final DosboxEngine engine;
  final VoidCallback onClose;

  static const _rows = <List<(String, int)>>[
    [
      ('Esc', RetroKey.escape),
      ('F1', RetroKey.f1),
      ('F2', RetroKey.f2),
      ('F3', RetroKey.f3),
      ('F4', RetroKey.f4),
      ('F5', RetroKey.f5),
      ('F6', RetroKey.f6),
      ('F7', RetroKey.f7),
      ('F8', RetroKey.f8),
      ('F9', RetroKey.f9),
      ('F10', RetroKey.f10),
    ],
    [
      ('1', RetroKey.key1),
      ('2', RetroKey.key2),
      ('3', RetroKey.key3),
      ('4', RetroKey.key4),
      ('5', RetroKey.key5),
      ('6', RetroKey.key6),
      ('7', RetroKey.key7),
      ('8', RetroKey.key8),
      ('9', RetroKey.key9),
      ('0', RetroKey.key0),
      ('⌫', RetroKey.backspace),
    ],
    [
      ('Q', RetroKey.q),
      ('W', RetroKey.w),
      ('E', RetroKey.e),
      ('R', RetroKey.r),
      ('T', RetroKey.t),
      ('Y', RetroKey.y),
      ('U', RetroKey.u),
      ('I', RetroKey.i),
      ('O', RetroKey.o),
      ('P', RetroKey.p),
    ],
    [
      ('A', RetroKey.a),
      ('S', RetroKey.s),
      ('D', RetroKey.d),
      ('F', RetroKey.f),
      ('G', RetroKey.g),
      ('H', RetroKey.h),
      ('J', RetroKey.j),
      ('K', RetroKey.k),
      ('L', RetroKey.l),
      ('↵', RetroKey.enter),
    ],
    [
      ('Ctrl', RetroKey.lCtrl),
      ('Alt', RetroKey.lAlt),
      ('Z', RetroKey.z),
      ('X', RetroKey.x),
      ('C', RetroKey.c),
      ('V', RetroKey.v),
      ('B', RetroKey.b),
      ('N', RetroKey.n),
      ('M', RetroKey.m),
      ('Space', RetroKey.space),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
      decoration: const BoxDecoration(
        color: Color(0xE6141820),
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text(
                  'PC 虚拟键盘',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_hide, color: Colors.white70, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  for (final (label, code) in row)
                    Expanded(
                      flex: label == 'Space' ? 2 : 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _MiniKey(
                          label: label,
                          onChanged: (d) => engine.sendKeyEvent(code, d),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniKey extends StatefulWidget {
  const _MiniKey({required this.label, required this.onChanged});

  final String label;
  final ValueChanged<bool> onChanged;

  @override
  State<_MiniKey> createState() => _MiniKeyState();
}

class _MiniKeyState extends State<_MiniKey> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _down ? Colors.cyan : const Color(0xFF28303D),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}
