import 'dart:async';

import 'package:flutter/services.dart';

class RemoteLongPress {
  RemoteLongPress({this.duration = const Duration(milliseconds: 650)});

  final Duration duration;
  Timer? _timer;
  LogicalKeyboardKey? _activeKey;
  bool _longTriggered = false;

  bool handle(
    KeyEvent event, {
    required bool enabled,
    required VoidCallback onShortPress,
    required VoidCallback onLongPress,
  }) {
    final key = event.logicalKey;
    final isSelect =
        key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
    if (!enabled || !isSelect) return false;

    if (event is KeyDownEvent && _activeKey == null) {
      _activeKey = key;
      _longTriggered = false;
      _timer = Timer(duration, () {
        _longTriggered = true;
        onLongPress();
      });
      return true;
    }
    if (event is KeyRepeatEvent) return true;
    if (event is KeyUpEvent && _activeKey != null) {
      _timer?.cancel();
      final shortPress = !_longTriggered;
      _activeKey = null;
      _longTriggered = false;
      if (shortPress) onShortPress();
      return true;
    }
    return true;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _activeKey = null;
    _longTriggered = false;
  }
}
