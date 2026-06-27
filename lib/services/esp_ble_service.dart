import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/utils/constants.dart';
import 'distance_alert_source.dart';

// Re-export the shared verdict/state types so existing imports of this file
// (e.g. home_screen) keep resolving `ObstacleVerdict` / `SensorLinkState`.
export 'distance_alert_source.dart';

/// BLE service that streams raw distance values from the ESP32 firmware
/// (`Thesis_esp/smart_cane_ble`) and exposes a derived alert verdict.
///
/// The ESP32 sends ASCII strings like `"142.3"` (cm) or `"-1"` (no echo)
/// every ~200 ms. Verdict thresholds live in `AppConstants` so they can
/// be tuned without reflashing the firmware.
///
/// Implements [DistanceAlertSource] so it is interchangeable with the
/// Pi-over-WiFi distance source ([PiDistanceService]).
class EspBleService extends ChangeNotifier implements DistanceAlertSource {
  static EspBleService? _instance;
  static EspBleService get instance => _instance ??= EspBleService._();
  EspBleService._();

  SensorLinkState _state = SensorLinkState.disconnected;
  String _statusMessage = 'Initializing...';
  BluetoothDevice? _connectedDevice;
  double? _latestDistance;
  String _lastRawValue = '';
  bool _autoReconnect = true;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  /// Optional callback fired when verdict transitions (e.g. SAFE → CRITICAL).
  /// Use this to drive TTS announcements without spamming on every reading.
  @override
  void Function(ObstacleVerdict verdict)? onVerdictChanged;
  ObstacleVerdict _lastNotifiedVerdict = ObstacleVerdict.noData;

  @override
  SensorLinkState get state => _state;
  @override
  bool get isConnected => _state == SensorLinkState.connected;
  @override
  bool get isScanning => _state == SensorLinkState.scanning;
  @override
  String get statusMessage => _statusMessage;
  String get lastRawValue => _lastRawValue;
  @override
  double? get latestDistance => _latestDistance;
  String? get connectedDeviceName => _connectedDevice?.platformName;

  /// Verdict derived from the current distance using the shared thresholds in
  /// `AppConstants`. Returns `noData` when no valid reading is available.
  @override
  ObstacleVerdict get verdict => verdictForDistanceCm(_latestDistance);

  @override
  Future<void> initialize() async {
    if (await FlutterBluePlus.isSupported == false) {
      _updateState(SensorLinkState.error, 'Bluetooth not supported on this device');
      return;
    }

    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((s) {
      debugPrint('>> ESP BLE: Adapter state: $s');
      if (s == BluetoothAdapterState.on) {
        if (_state == SensorLinkState.bluetoothOff ||
            _state == SensorLinkState.disconnected) {
          _updateState(
            SensorLinkState.disconnected,
            'Bluetooth on. Ready to scan.',
          );
          startScanning();
        }
      } else {
        _updateState(SensorLinkState.bluetoothOff, 'Bluetooth is off.');
      }
    });

    final current = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => BluetoothAdapterState.unknown,
        );

    if (current == BluetoothAdapterState.on) {
      _updateState(SensorLinkState.disconnected, 'Ready to scan for ESP32.');
      startScanning();
    } else if (current == BluetoothAdapterState.off) {
      _updateState(SensorLinkState.bluetoothOff, 'Bluetooth is off.');
    } else {
      _updateState(SensorLinkState.error, 'Bluetooth adapter not available.');
    }
  }

  @override
  Future<void> startScanning() async {
    if (_state == SensorLinkState.scanning || _state == SensorLinkState.connected) {
      return;
    }
    if (_state == SensorLinkState.bluetoothOff) {
      _updateState(SensorLinkState.bluetoothOff, 'Cannot scan — Bluetooth off.');
      return;
    }

    _updateState(SensorLinkState.scanning, 'Scanning for ESP32...');
    debugPrint('>> ESP BLE: ===== STARTING SCAN =====');

    // Try bonded list first — Android does not surface already-paired
    // devices in active scan results.
    try {
      final bonded = await FlutterBluePlus.bondedDevices;
      for (final device in bonded) {
        if (device.platformName.toLowerCase().contains(
          AppConstants.espBleDeviceName.toLowerCase(),
        )) {
          debugPrint('>> ESP BLE: ★ Found in bonded list — connecting');
          _connectToDevice(device);
          return;
        }
      }
    } catch (e) {
      debugPrint('>> ESP BLE: Could not read bonded devices: $e');
    }

    try {
      final scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName;
          final advName = r.advertisementData.advName;
          final match = name.isNotEmpty ? name : advName;
          if (match.toLowerCase().contains(
            AppConstants.espBleDeviceName.toLowerCase(),
          )) {
            debugPrint('>> ESP BLE: ★★★ ESP32 FOUND, connecting...');
            FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            return;
          }
        }
      }, onError: (e) => debugPrint('>> ESP BLE: Scan error: $e'));
      FlutterBluePlus.cancelWhenScanComplete(scanSub);

      await FlutterBluePlus.startScan(
        timeout: AppConstants.bleScanTimeout,
        androidUsesFineLocation: false,
      );

      await FlutterBluePlus.isScanning.where((v) => v == false).first;

      if (_state == SensorLinkState.scanning) {
        _updateState(
          SensorLinkState.disconnected,
          'ESP32 not found. Tap to scan again.',
        );
        if (_autoReconnect) {
          Future.delayed(AppConstants.bleReconnectDelay, () {
            if (_state == SensorLinkState.disconnected) startScanning();
          });
        }
      }
    } catch (e) {
      debugPrint('>> ESP BLE: Scan error: $e');
      _updateState(SensorLinkState.error, 'Scan error: $e');
    }
  }

  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    if (_state == SensorLinkState.scanning) {
      _updateState(SensorLinkState.disconnected, 'Scan stopped.');
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _updateState(
      SensorLinkState.connecting,
      'Connecting to ${device.platformName}...',
    );

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      _connectedDevice = device;
      debugPrint('>> ESP BLE: ✓ Connected to ${device.platformName}');

      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          debugPrint('>> ESP BLE: ✗ Disconnected');
          _handleDisconnection();
        }
      });

      await _discoverAndSubscribe(device);
    } catch (e) {
      debugPrint('>> ESP BLE: ✗ Connect failed: $e');
      _connectedDevice = null;
      _updateState(SensorLinkState.error, 'Connection failed: $e');
      _scheduleReconnect();
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    _updateState(SensorLinkState.connecting, 'Discovering ESP services...');

    try {
      try {
        await device.clearGattCache();
      } catch (_) {}

      final services = await device.discoverServices();
      final targetService = Guid(AppConstants.espBleServiceUuid);
      final targetChar = Guid(AppConstants.espBleDistanceCharUuid);

      BluetoothService? espService;
      for (final s in services) {
        if (s.uuid == targetService) {
          espService = s;
          break;
        }
      }
      if (espService == null) {
        _updateState(SensorLinkState.error, 'ESP service not found.');
        return;
      }

      BluetoothCharacteristic? distChar;
      for (final c in espService.characteristics) {
        if (c.uuid == targetChar) {
          distChar = c;
          break;
        }
      }
      if (distChar == null) {
        _updateState(SensorLinkState.error, 'Distance characteristic not found.');
        return;
      }

      final sub = distChar.onValueReceived.listen((value) {
        final raw = utf8.decode(value).trim();
        _onDistanceReceived(raw);
      });
      device.cancelWhenDisconnected(sub, delayed: true, next: true);

      await distChar.setNotifyValue(true);

      _updateState(
        SensorLinkState.connected,
        'Connected to ${device.platformName} ✓',
      );
      debugPrint('>> ESP BLE: ===== READY — STREAMING DISTANCE =====');
    } catch (e) {
      debugPrint('>> ESP BLE: Discover/subscribe failed: $e');
      _updateState(SensorLinkState.error, 'Setup failed: $e');
    }
  }

  void _onDistanceReceived(String raw) {
    _lastRawValue = raw;
    final parsed = double.tryParse(raw);
    _latestDistance = (parsed == null || parsed < 0) ? null : parsed;

    final newVerdict = verdict;
    if (newVerdict != _lastNotifiedVerdict) {
      _lastNotifiedVerdict = newVerdict;
      onVerdictChanged?.call(newVerdict);
    }

    notifyListeners();
  }

  void _handleDisconnection() {
    _connectedDevice = null;
    _latestDistance = null;
    _lastNotifiedVerdict = ObstacleVerdict.noData;
    _updateState(SensorLinkState.disconnected, 'ESP32 disconnected.');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_autoReconnect) return;
    Future.delayed(AppConstants.bleReconnectDelay, () {
      if (_state == SensorLinkState.disconnected || _state == SensorLinkState.error) {
        startScanning();
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _autoReconnect = false;
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      debugPrint('>> ESP BLE: Disconnect error: $e');
    }
    _connectedDevice = null;
    _latestDistance = null;
    _updateState(SensorLinkState.disconnected, 'Disconnected.');
  }

  void enableAutoReconnect() {
    _autoReconnect = true;
    if (_state == SensorLinkState.disconnected) startScanning();
  }

  void _updateState(SensorLinkState s, String msg) {
    _state = s;
    _statusMessage = msg;
    debugPrint('>> ESP BLE: STATE → $s: $msg');
    notifyListeners();
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }
}
