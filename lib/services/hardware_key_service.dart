import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Listens for hardware-key events forwarded from the Android side
/// ([MainActivity.onKeyDown] / [onKeyUp]) over a [MethodChannel].
///
/// The native side intercepts both Volume-Up and Volume-Down (and consumes
/// them so system volume isn't affected) and forwards them as a single
/// abstract "volume key" stream — Dart doesn't need to know which key the
/// user pressed.
///
/// Usage (push-to-talk pattern):
/// ```
/// HardwareKeyService.instance.setVolumeKeyHandlers(
///   onDown: () => voice.startListening(),
///   onUp:   () => voice.stopListening(),
/// );
/// ```
///
/// Only one handler pair is active at a time (last writer wins).  Wire it up
/// once at app start — the channel is process-wide and survives navigation.
class HardwareKeyService {
  HardwareKeyService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static HardwareKeyService? _instance;
  static HardwareKeyService get instance =>
      _instance ??= HardwareKeyService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.test_app_1/hardware_keys');

  VoidCallback? _onDown;
  VoidCallback? _onUp;

  /// Tracks whether a key is currently held — guards against duplicate
  /// `onDown` / `onUp` callbacks that some Android versions emit when the
  /// key event is consumed mid-stream.
  bool _isPressed = false;

  /// Register handlers for the press (down) and release (up) phases of the
  /// volume keys.  Pass `null` for either to clear it.
  void setVolumeKeyHandlers({VoidCallback? onDown, VoidCallback? onUp}) {
    _onDown = onDown;
    _onUp = onUp;
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onVolumeKeyDown':
        if (_isPressed) return null;
        _isPressed = true;
        debugPrint('HardwareKeyService: volume key DOWN');
        _onDown?.call();
        return null;
      case 'onVolumeKeyUp':
        if (!_isPressed) return null;
        _isPressed = false;
        debugPrint('HardwareKeyService: volume key UP');
        _onUp?.call();
        return null;
      default:
        return null;
    }
  }
}
