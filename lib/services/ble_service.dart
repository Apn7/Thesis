import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/utils/constants.dart';

/// BLE connection states for UI display
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  bluetoothOff,
  error,
}

/// Parsed alert data from the Raspberry Pi
/// Format: "LEVEL:OBJECT_NAME:CONFIDENCE:POSITION"
class BleAlert {
  final String level;      // CRITICAL, WARNING, CAUTION, TEST
  final String objectName; // Person, Car, etc.
  final String confidence; // 87%
  final String position;   // left, center, right
  final String rawMessage;

  BleAlert({
    required this.level,
    required this.objectName,
    required this.confidence,
    required this.position,
    required this.rawMessage,
  });

  /// Parse "CRITICAL:Person:87%:center" format from Pi
  factory BleAlert.parse(String message) {
    final parts = message.split(':');
    if (parts.length >= 4) {
      return BleAlert(
        level: parts[0].trim(),
        objectName: parts[1].trim(),
        confidence: parts[2].trim(),
        position: parts[3].trim(),
        rawMessage: message,
      );
    }
    return BleAlert(
      level: 'INFO',
      objectName: message,
      confidence: '',
      position: '',
      rawMessage: message,
    );
  }

  bool get isCritical => level == 'CRITICAL';
  bool get isWarning => level == 'WARNING';
  bool get isCaution => level == 'CAUTION';
  bool get isTest => level == 'TEST';

  String get displayMessage {
    if (confidence.isNotEmpty && position.isNotEmpty) {
      return '$level: $objectName ($confidence) — $position';
    }
    return rawMessage;
  }
}

/// BLE Service — handles Bluetooth Low Energy communication with the Smart Cane
/// 
/// Follows the official flutter_blue_plus patterns exactly:
/// 1. Listen to onScanResults → cancelWhenScanComplete
/// 2. Connect → discoverServices
/// 3. Listen to onValueReceived → cancelWhenDisconnected → setNotifyValue(true)
class BleService extends ChangeNotifier {
  static BleService? _instance;
  
  // BLE state
  BleConnectionState _state = BleConnectionState.disconnected;
  BluetoothDevice? _connectedDevice;
  String _statusMessage = 'Initializing...';
  String _latestAlert = '';
  BleAlert? _latestParsedAlert;
  bool _autoReconnect = true;
  
  // Subscriptions
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  
  // Callback for incoming alerts (used by HomeScreen)
  Function(String message)? onAlertReceived;
  
  // Singleton
  static BleService get instance {
    _instance ??= BleService._();
    return _instance!;
  }
  
  BleService._();
  
  // Getters
  BleConnectionState get state => _state;
  bool get isConnected => _state == BleConnectionState.connected;
  bool get isScanning => _state == BleConnectionState.scanning;
  String get statusMessage => _statusMessage;
  String get latestAlert => _latestAlert;
  BleAlert? get latestParsedAlert => _latestParsedAlert;
  String? get connectedDeviceName => _connectedDevice?.platformName;
  
  /// Initialize BLE — check adapter state and start monitoring
  Future<void> initialize() async {
    // Check if Bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
      _updateState(BleConnectionState.error, 'Bluetooth not supported on this device');
      return;
    }
    
    // Monitor Bluetooth adapter state (on/off)
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((adapterState) {
      debugPrint('>> BLE: Adapter state: $adapterState');
      if (adapterState == BluetoothAdapterState.on) {
        if (_state == BleConnectionState.bluetoothOff || 
            _state == BleConnectionState.disconnected) {
          _updateState(BleConnectionState.disconnected, 'Bluetooth is on. Ready to scan.');
          startScanning();
        }
      } else {
        _updateState(BleConnectionState.bluetoothOff, 'Bluetooth is off. Please turn it on.');
      }
    });
    
    // Check current state — wait for adapter to be ready
    debugPrint('>> BLE: Waiting for adapter state...');
    final currentState = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.unknown);
    
    debugPrint('>> BLE: Current adapter state: $currentState');
    if (currentState == BluetoothAdapterState.on) {
      _updateState(BleConnectionState.disconnected, 'Ready to scan for Smart Cane.');
      startScanning();
    } else if (currentState == BluetoothAdapterState.off) {
      _updateState(BleConnectionState.bluetoothOff, 'Bluetooth is off. Please turn it on.');
    } else {
      _updateState(BleConnectionState.error, 'Bluetooth adapter not available.');
    }
  }
  
  /// Scan for the SmartCane BLE peripheral
  /// Uses the official flutter_blue_plus pattern: 
  ///   onScanResults.listen → cancelWhenScanComplete → startScan
  Future<void> startScanning() async {
    if (_state == BleConnectionState.scanning || _state == BleConnectionState.connected) {
      debugPrint('>> BLE: Already scanning or connected, skipping scan');
      return;
    }
    
    if (_state == BleConnectionState.bluetoothOff) {
      _updateState(BleConnectionState.bluetoothOff, 'Cannot scan — Bluetooth is off.');
      return;
    }
    
    _updateState(BleConnectionState.scanning, 'Scanning for Smart Cane...');
    debugPrint('>> BLE: ===== STARTING SCAN =====');
    debugPrint('>> BLE: Looking for device name containing: "${AppConstants.bleDeviceName}"');
    
    try {
      // Step 1: Set up scan result listener (BEFORE starting scan)
      var scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
        debugPrint('>> BLE: Scan callback - ${results.length} results');
        for (ScanResult r in results) {
          final name = r.device.platformName;
          final advName = r.advertisementData.advName;
          
          if (name.isNotEmpty || advName.isNotEmpty) {
            debugPrint('>> BLE: Found: platformName="$name", advName="$advName", id=${r.device.remoteId}, rssi=${r.rssi}');
          }
          
          // Match by platformName OR advertisementData.advName
          final matchName = name.isNotEmpty ? name : advName;
          if (matchName.toLowerCase().contains(AppConstants.bleDeviceName.toLowerCase())) {
            debugPrint('>> BLE: ★★★ SmartCane FOUND! Stopping scan and connecting...');
            FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            return;
          }
        }
      }, onError: (e) {
        debugPrint('>> BLE: Scan results error: $e');
      });
      
      // Step 2: Auto-cancel subscription when scan completes (official pattern)
      FlutterBluePlus.cancelWhenScanComplete(scanSubscription);
      
      // Step 3: Start the scan with name filter
      await FlutterBluePlus.startScan(
        timeout: AppConstants.bleScanTimeout,
        androidUsesFineLocation: false,
      );
      
      // Step 4: Wait for scan to complete
      debugPrint('>> BLE: Waiting for scan to complete...');
      await FlutterBluePlus.isScanning.where((val) => val == false).first;
      debugPrint('>> BLE: Scan completed');
      
      // If still scanning state (not found device), handle timeout
      if (_state == BleConnectionState.scanning) {
        debugPrint('>> BLE: ✗ SmartCane NOT found after scan');
        _updateState(BleConnectionState.disconnected, 
          'Smart Cane not found. Tap to scan again.');
        
        // Auto-retry after delay
        if (_autoReconnect) {
          debugPrint('>> BLE: Will auto-retry in ${AppConstants.bleReconnectDelay.inSeconds}s');
          Future.delayed(AppConstants.bleReconnectDelay, () {
            if (_state == BleConnectionState.disconnected) {
              startScanning();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('>> BLE: Scan error: $e');
      _updateState(BleConnectionState.error, 'Scan error: $e');
    }
  }
  
  /// Stop scanning
  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    if (_state == BleConnectionState.scanning) {
      _updateState(BleConnectionState.disconnected, 'Scan stopped.');
    }
  }
  
  /// Connect to the SmartCane BLE device
  /// Uses the official flutter_blue_plus pattern
  Future<void> _connectToDevice(BluetoothDevice device) async {
    _updateState(BleConnectionState.connecting, 'Connecting to ${device.platformName}...');
    debugPrint('>> BLE: ===== CONNECTING =====');
    debugPrint('>> BLE: Device: ${device.platformName} (${device.remoteId})');
    
    try {
      // Step 1: Connect to device
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      
      _connectedDevice = device;
      debugPrint('>> BLE: ✓ Connected to ${device.platformName}');
      
      // Step 2: Set up disconnect listener AFTER successful connection
      // Listen for disconnection events
      device.connectionState.listen((state) {
        debugPrint('>> BLE: Connection state changed → $state');
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('>> BLE: ✗ Device DISCONNECTED');
          _handleDisconnection();
        }
      });
      
      // Step 3: Discover services and subscribe
      await _discoverAndSubscribe(device);
      
    } catch (e) {
      debugPrint('>> BLE: ✗ Connection FAILED: $e');
      _connectedDevice = null;
      _updateState(BleConnectionState.error, 'Connection failed: $e');
      _scheduleReconnect();
    }
  }
  
  /// Discover GATT services and subscribe to the Alert characteristic
  /// Uses official flutter_blue_plus pattern:
  ///   onValueReceived.listen → cancelWhenDisconnected → setNotifyValue(true)
  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    debugPrint('>> BLE: ===== DISCOVERING SERVICES =====');
    _updateState(BleConnectionState.connecting, 'Discovering services...');
    
    try {
      // Step 1: Discover all services
      List<BluetoothService> services = await device.discoverServices();
      debugPrint('>> BLE: Found ${services.length} services:');
      
      // Log ALL services for debugging
      for (var service in services) {
        debugPrint('>> BLE:   Service: ${service.uuid} (${service.characteristics.length} characteristics)');
        for (var char in service.characteristics) {
          debugPrint('>> BLE:     Char: ${char.uuid} [read=${char.properties.read}, notify=${char.properties.notify}, indicate=${char.properties.indicate}]');
        }
      }
      
      // Step 2: Find our Smart Cane service by UUID
      final targetServiceUuid = Guid(AppConstants.bleServiceUuid);
      debugPrint('>> BLE: Looking for service UUID: $targetServiceUuid');
      
      BluetoothService? caneService;
      for (var service in services) {
        if (service.uuid == targetServiceUuid) {
          caneService = service;
          debugPrint('>> BLE: ✓ Smart Cane service FOUND!');
          break;
        }
      }
      
      if (caneService == null) {
        // Try case-insensitive string matching as fallback
        final targetStr = AppConstants.bleServiceUuid.toLowerCase();
        for (var service in services) {
          if (service.uuid.toString().toLowerCase() == targetStr || 
              service.uuid.toString().toLowerCase().contains(targetStr)) {
            caneService = service;
            debugPrint('>> BLE: ✓ Smart Cane service found via string match: ${service.uuid}');
            break;
          }
        }
      }
      
      if (caneService == null) {
        debugPrint('>> BLE: ✗ Smart Cane service NOT FOUND among ${services.length} services');
        _updateState(BleConnectionState.error, 
          'Service not found. Check Pi GATT config. Found ${services.length} services.');
        return;
      }
      
      // Step 3: Find the Alert characteristic
      final targetAlertUuid = Guid(AppConstants.bleAlertCharUuid);
      debugPrint('>> BLE: Looking for alert char UUID: $targetAlertUuid');
      
      BluetoothCharacteristic? alertChar;
      for (var char in caneService.characteristics) {
        if (char.uuid == targetAlertUuid) {
          alertChar = char;
          debugPrint('>> BLE: ✓ Alert characteristic FOUND!');
          break;
        }
      }
      
      // Fallback: string comparison
      if (alertChar == null) {
        final targetStr = AppConstants.bleAlertCharUuid.toLowerCase();
        for (var char in caneService.characteristics) {
          if (char.uuid.toString().toLowerCase() == targetStr ||
              char.uuid.toString().toLowerCase().contains(targetStr)) {
            alertChar = char;
            debugPrint('>> BLE: ✓ Alert characteristic found via string match: ${char.uuid}');
            break;
          }
        }
      }
      
      if (alertChar == null) {
        debugPrint('>> BLE: ✗ Alert characteristic NOT FOUND');
        _updateState(BleConnectionState.error, 
          'Alert characteristic not found. Check Pi GATT config.');
        return;
      }
      
      // Step 4: Subscribe to notifications — OFFICIAL flutter_blue_plus pattern:
      //   a) Listen to onValueReceived FIRST
      //   b) cancelWhenDisconnected to auto-cleanup
      //   c) THEN call setNotifyValue(true)
      debugPrint('>> BLE: ===== SUBSCRIBING TO NOTIFICATIONS =====');
      debugPrint('>> BLE: Char properties: read=${alertChar.properties.read}, notify=${alertChar.properties.notify}, indicate=${alertChar.properties.indicate}');
      
      // Step 4a: Set up listener FIRST
      final subscription = alertChar.onValueReceived.listen((value) {
        final message = utf8.decode(value).trim();
        debugPrint('>> BLE: ★ ALERT RECEIVED: "$message" (${value.length} bytes)');
        
        if (message.isNotEmpty) {
          _latestAlert = message;
          _latestParsedAlert = BleAlert.parse(message);
          notifyListeners();
          onAlertReceived?.call(message);
        }
      });
      
      // Step 4b: Auto-cancel when device disconnects (official pattern)
      device.cancelWhenDisconnected(subscription, delayed: true, next: true);
      debugPrint('>> BLE: ✓ Listener set up with cancelWhenDisconnected');
      
      // Step 4c: NOW enable notifications → triggers StartNotify on Pi
      debugPrint('>> BLE: Calling setNotifyValue(true)...');
      await alertChar.setNotifyValue(true);
      debugPrint('>> BLE: ✓ setNotifyValue(true) DONE — Pi should show StartNotify');
      
      // Success!
      _updateState(BleConnectionState.connected, 
        'Connected to ${device.platformName} ✓');
      debugPrint('>> BLE: ===== READY — LISTENING FOR ALERTS =====');
      
    } catch (e, stackTrace) {
      debugPrint('>> BLE: ✗ Service discovery/subscription FAILED: $e');
      debugPrint('>> BLE: Stack trace: $stackTrace');
      _updateState(BleConnectionState.error, 'Setup failed: $e');
    }
  }
  
  /// Handle device disconnection
  void _handleDisconnection() {
    _connectedDevice = null;
    _updateState(BleConnectionState.disconnected, 'Smart Cane disconnected.');
    _scheduleReconnect();
  }
  
  /// Schedule auto-reconnect attempt
  void _scheduleReconnect() {
    if (_autoReconnect) {
      debugPrint('>> BLE: Will retry scan in ${AppConstants.bleReconnectDelay.inSeconds}s');
      Future.delayed(AppConstants.bleReconnectDelay, () {
        if (_state == BleConnectionState.disconnected || 
            _state == BleConnectionState.error) {
          startScanning();
        }
      });
    }
  }
  
  /// Disconnect from the current device
  Future<void> disconnect() async {
    _autoReconnect = false;
    
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      debugPrint('>> BLE: Disconnect error: $e');
    }
    
    _connectedDevice = null;
    _updateState(BleConnectionState.disconnected, 'Disconnected.');
  }
  
  /// Enable auto-reconnect and start scanning
  void enableAutoReconnect() {
    _autoReconnect = true;
    if (_state == BleConnectionState.disconnected) {
      startScanning();
    }
  }
  
  /// Update state and notify UI listeners
  void _updateState(BleConnectionState newState, String message) {
    _state = newState;
    _statusMessage = message;
    debugPrint('>> BLE: STATE → $newState: $message');
    notifyListeners();
  }
  
  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }
}
