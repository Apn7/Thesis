import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/utils/constants.dart';
import 'distance_alert_source.dart';

/// Receives HC-SR04 distance readings from the Raspberry Pi over WiFi and
/// exposes them with the **same surface as [EspBleService]** (via
/// [DistanceAlertSource]), so it is a drop-in replacement for the ESP32 path.
/// The downstream alert/haptics/speech logic in `HomeScreen` is unchanged.
///
/// **Role reversal (identical to `PiFrameServer`):** although the *Pi* owns
/// the sensor, the **phone is the TCP server**. On a phone hotspot the Pi can
/// always reach the phone (its default gateway) but the phone can't reliably
/// address the Pi — so the Pi dials us. We bind
/// [AppConstants.piDistancePort] and accept its connection.
///
/// **Wire format:** newline-delimited ASCII centimetre readings, e.g.
/// `"142.3\n"` (cm) or `"-1\n"` (no valid reading). This mirrors the ESP32's
/// own string format, so parsing is identical (`double.tryParse` after trim;
/// negative ⇒ no-data). Matches the Pi's `SonarSender`.
///
/// **Newest-reading-wins:** readings are tiny and arrive ~5×/sec; there is no
/// value in queueing stale distances, so we keep only the latest.
class PiDistanceService extends ChangeNotifier implements DistanceAlertSource {
  static PiDistanceService? _instance;
  static PiDistanceService get instance => _instance ??= PiDistanceService._();
  PiDistanceService._();

  final int _port = AppConstants.piDistancePort;
  final int _maxLineBytes = AppConstants.piDistanceMaxLineBytes;

  ServerSocket? _server;
  Socket? _client;
  StreamSubscription<Uint8List>? _clientSub;

  /// Reassembly buffer for a line split across arbitrarily-chunked TCP reads.
  final BytesBuilder _lineBuf = BytesBuilder(copy: false);

  bool _disposed = false;

  // ── State (mirrors EspBleService) ───────────────────────────────────────
  SensorLinkState _state = SensorLinkState.disconnected;
  String _statusMessage = 'Initializing...';
  double? _latestDistance;
  String _lastRawValue = '';

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
  @override
  double? get latestDistance => _latestDistance;
  String get lastRawValue => _lastRawValue;
  String? get connectedDeviceName => _client?.remoteAddress.address;

  @override
  ObstacleVerdict get verdict => verdictForDistanceCm(_latestDistance);

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    await startScanning();
  }

  /// "Scanning" == binding the socket and waiting for the Pi to dial in. Named
  /// to match the BLE source so `HomeScreen`'s wiring is identical. Safe to
  /// call when already listening (no-op).
  @override
  Future<void> startScanning() async {
    if (_disposed) return;
    if (_server != null) return; // already bound
    try {
      // anyIPv4 so the Pi (on the hotspot subnet) can reach us; shared:false
      // because we want exactly one listener for this port.
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        shared: false,
      );
      _server!.listen(
        _onClient,
        onError: (Object e, StackTrace s) =>
            _setError('Server socket error: $e'),
        cancelOnError: false,
      );
      debugPrint('PiDistanceService: listening on 0.0.0.0:$_port');
      _updateState(
        SensorLinkState.scanning,
        'Waiting for cane sensor (WiFi)...',
      );
    } on Object catch (e) {
      // Most likely: port already in use (a stale instance, or two screens).
      _setError('Could not bind port $_port: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _dropClient(backToListening: false);
    final server = _server;
    _server = null;
    try {
      await server?.close();
    } on Object catch (e) {
      debugPrint('PiDistanceService: error closing server — $e');
    }
    if (!_disposed) _updateState(SensorLinkState.disconnected, 'Disconnected.');
  }

  @override
  void dispose() {
    _disposed = true;
    _dropClient(backToListening: false);
    _server?.close();
    _server = null;
    super.dispose();
  }

  // ── Client handling ─────────────────────────────────────────────────────

  void _onClient(Socket socket) {
    if (_disposed) {
      socket.destroy();
      return;
    }
    // Single producer expected. If a previous Pi link is still half-open (Pi
    // rebooted and redialed before our keepalive noticed), replace it — the
    // newest connection is the live one.
    if (_client != null) {
      debugPrint('PiDistanceService: replacing existing client connection');
      _dropClient(backToListening: false);
    }

    debugPrint(
      'PiDistanceService: client connected ${socket.remoteAddress.address}',
    );
    _client = socket;
    _lineBuf.clear();

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } on Object catch (_) {
      // Non-fatal; some platforms reject this.
    }

    _clientSub = socket.listen(
      _onData,
      onError: (Object e, StackTrace s) {
        debugPrint('PiDistanceService: client error — $e');
        _dropClient();
      },
      onDone: () {
        debugPrint('PiDistanceService: client disconnected');
        _dropClient();
      },
      cancelOnError: true,
    );
    _updateState(SensorLinkState.connected, 'Cane sensor connected (WiFi) ✓');
  }

  void _dropClient({bool backToListening = true}) {
    _clientSub?.cancel();
    _clientSub = null;
    final client = _client;
    _client = null;
    try {
      client?.destroy();
    } on Object catch (_) {}
    _lineBuf.clear();
    _latestDistance = null;

    // The link is gone — make the cane go quiet. Emitting a `noData` verdict
    // here lets the downstream handler stop any ongoing vibration/alert tone,
    // exactly as it does when a real reading clears (safety-critical: a lost
    // link must not leave the user buzzing or believing the path is unknown).
    if (_lastNotifiedVerdict != ObstacleVerdict.noData) {
      _lastNotifiedVerdict = ObstacleVerdict.noData;
      onVerdictChanged?.call(ObstacleVerdict.noData);
    }

    // Back to listening if the server is still up and we didn't error out.
    if (backToListening &&
        !_disposed &&
        _server != null &&
        _state == SensorLinkState.connected) {
      _updateState(
        SensorLinkState.scanning,
        'Waiting for cane sensor (WiFi)...',
      );
    }
  }

  // ── Line reassembly ─────────────────────────────────────────────────────

  void _onData(Uint8List chunk) {
    _lineBuf.add(chunk);
    // A newline should arrive every few bytes; if the buffer grows past a
    // plausible line length the stream is garbled — sever and let the Pi
    // redial rather than buffer unboundedly.
    if (_lineBuf.length > _maxLineBytes) {
      debugPrint('PiDistanceService: line exceeds $_maxLineBytes B — dropping');
      _dropClient();
      return;
    }
    _drainLines();
  }

  void _drainLines() {
    final bytes = _lineBuf.takeBytes();
    int start = 0;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        // '\n'
        _onLine(Uint8List.sublistView(bytes, start, i));
        start = i + 1;
      }
    }
    // Re-buffer the unconsumed tail (a partial line).
    if (start < bytes.length) {
      _lineBuf.add(Uint8List.sublistView(bytes, start));
    }
  }

  void _onLine(Uint8List lineBytes) {
    String raw;
    try {
      raw = utf8.decode(lineBytes).trim();
    } on FormatException {
      return; // ignore a corrupt line, keep the link alive
    }
    if (raw.isEmpty) return; // tolerate "\r\n" / blank keepalive lines

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

  // ── State helpers ───────────────────────────────────────────────────────

  void _updateState(SensorLinkState s, String msg) {
    _state = s;
    _statusMessage = msg;
    debugPrint('PiDistanceService: STATE → $s: $msg');
    notifyListeners();
  }

  void _setError(String message) {
    debugPrint('PiDistanceService: $message');
    if (_disposed) return;
    _statusMessage = message;
    _state = SensorLinkState.error;
    notifyListeners();
  }
}
