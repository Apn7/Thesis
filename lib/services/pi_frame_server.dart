import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/utils/constants.dart';

/// Lifecycle/connection state of the [PiFrameServer], surfaced to the UI.
enum PiServerState {
  /// Not started, or stopped.
  idle,

  /// Socket bound; waiting for the Pi to dial in.
  listening,

  /// A Pi is connected and (presumably) streaming frames.
  streaming,

  /// Fatal setup error (e.g. the port is already in use). See [errorMessage].
  error,
}

/// Receives camera frames from the Raspberry Pi over TCP and exposes the
/// **newest** one, dropping any backlog.
///
/// Role reversal note: although the *Pi* is the camera, the **phone is the
/// TCP server**. On a phone hotspot the Pi can always reach the phone (its
/// default gateway), but the phone can't reliably address the Pi — so the Pi
/// dials us. We bind [AppConstants.piFramePort] and accept its connection.
///
/// Wire format (see [AppConstants.piFrameHeaderBytes]): a 4-byte big-endian
/// unsigned length, then that many JPEG bytes, repeated. TCP is a byte stream
/// with no message boundaries, so [_drain] reassembles frames across
/// arbitrarily-chunked reads.
///
/// Newest-frame-wins: detection (`YOLO.predict`) is slower than the frame
/// rate, so we keep only [latestFrame] and bump [frameId] on each arrival.
/// Consumers process the latest frame when free and skip the rest — there is
/// no unbounded queue to fall behind on.
class PiFrameServer extends ChangeNotifier {
  PiFrameServer({int? port, int? maxFrameBytes})
    : _port = port ?? AppConstants.piFramePort,
      _maxFrameBytes = maxFrameBytes ?? AppConstants.piMaxFrameBytes;

  final int _port;
  final int _maxFrameBytes;

  ServerSocket? _server;
  Socket? _client;
  StreamSubscription<Uint8List>? _clientSub;

  // Reassembly buffer + the length of the frame we're currently filling
  // (null until a header has been parsed).
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int? _expectedLen;

  bool _disposed = false;

  // ── Public state ──────────────────────────────────────────────────────
  PiServerState _state = PiServerState.idle;
  PiServerState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// The most recently received complete JPEG frame, or null if none yet.
  Uint8List? _latestFrame;
  Uint8List? get latestFrame => _latestFrame;

  /// Monotonic id incremented on every received frame. Consumers compare it
  /// against the last id they processed to know whether [latestFrame] is new.
  int _frameId = 0;
  int get frameId => _frameId;

  /// Total frames received since [start] — for the on-screen counter.
  int _framesReceived = 0;
  int get framesReceived => _framesReceived;

  String? get clientAddress => _client?.remoteAddress.address;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Binds the server socket. Safe to call when already listening (no-op).
  Future<void> start() async {
    if (_disposed) return;
    if (_server != null) return; // already started
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
      debugPrint('PiFrameServer: listening on 0.0.0.0:$_port');
      _setState(PiServerState.listening);
    } on Object catch (e) {
      // Most likely: port already in use (a stale instance, or two screens).
      _setError('Could not bind port $_port: $e');
    }
  }

  /// Closes the client and server sockets and resets to [PiServerState.idle].
  /// Frame data ([latestFrame]) is retained so a paused screen can still show
  /// the last frame; call again or [dispose] to fully tear down.
  Future<void> stop() async {
    _dropClient();
    final server = _server;
    _server = null;
    try {
      await server?.close();
    } on Object catch (e) {
      debugPrint('PiFrameServer: error closing server — $e');
    }
    if (!_disposed) _setState(PiServerState.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    // Fire-and-forget; sockets close asynchronously but we won't touch them.
    _dropClient();
    _server?.close();
    _server = null;
    super.dispose();
  }

  // ── Client handling ───────────────────────────────────────────────────

  void _onClient(Socket socket) {
    if (_disposed) {
      socket.destroy();
      return;
    }
    // Single producer expected. If a previous Pi link is still half-open
    // (e.g. Pi rebooted and redialed before our TCP keepalive noticed the
    // drop), replace it — the newest connection is the live one.
    if (_client != null) {
      debugPrint('PiFrameServer: replacing existing client connection');
      _dropClient();
    }

    debugPrint('PiFrameServer: client connected ${socket.remoteAddress.address}');
    _client = socket;
    _resetParser();
    _framesReceived = 0;

    // Detect dead peers faster than the default OS timeout.
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } on Object catch (_) {
      // Non-fatal; some platforms reject this.
    }

    _clientSub = socket.listen(
      _onData,
      onError: (Object e, StackTrace s) {
        debugPrint('PiFrameServer: client error — $e');
        _dropClient();
      },
      onDone: () {
        debugPrint('PiFrameServer: client disconnected');
        _dropClient();
      },
      cancelOnError: true,
    );
    _setState(PiServerState.streaming);
  }

  void _dropClient() {
    _clientSub?.cancel();
    _clientSub = null;
    final client = _client;
    _client = null;
    try {
      client?.destroy();
    } on Object catch (_) {}
    _resetParser();
    // Back to listening if the server is still up and we didn't error out.
    if (!_disposed && _server != null && _state == PiServerState.streaming) {
      _setState(PiServerState.listening);
    }
  }

  void _resetParser() {
    _buffer.clear();
    _expectedLen = null;
  }

  // ── Frame reassembly ──────────────────────────────────────────────────

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    _drain();
  }

  /// Pulls as many complete frames as are available out of [_buffer],
  /// emitting each, and keeps the trailing partial bytes for next time.
  void _drain() {
    // takeBytes() returns the accumulated bytes AND clears the builder, so we
    // own [bytes] and re-stash whatever is left over at the end.
    Uint8List bytes = _buffer.takeBytes();
    int offset = 0;
    final header = AppConstants.piFrameHeaderBytes;

    while (true) {
      if (_expectedLen == null) {
        if (bytes.length - offset < header) break; // wait for full header
        final len = ByteData.sublistView(
          bytes,
          offset,
          offset + header,
        ).getUint32(0, Endian.big);
        offset += header;

        // Guard against corruption / desync: an implausible length means the
        // stream is no longer aligned. Reading it as a frame would either
        // OOM or stay desynced forever, so we sever and let the Pi redial.
        if (len <= 0 || len > _maxFrameBytes) {
          debugPrint('PiFrameServer: bad frame length $len — dropping client');
          _dropClient();
          return;
        }
        _expectedLen = len;
      }

      final need = _expectedLen!;
      if (bytes.length - offset < need) break; // wait for full payload

      // Copy out an independent frame (sublistView would alias [bytes], which
      // we discard below).
      final frame = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset, offset + need),
      );
      offset += need;
      _expectedLen = null;
      _emitFrame(frame);
    }

    // Re-buffer the unconsumed tail.
    if (offset < bytes.length) {
      _buffer.add(Uint8List.sublistView(bytes, offset));
    }
  }

  void _emitFrame(Uint8List frame) {
    if (_disposed) return;
    _latestFrame = frame;
    _frameId++;
    _framesReceived++;
    notifyListeners();
  }

  // ── State helpers ─────────────────────────────────────────────────────

  void _setState(PiServerState s) {
    if (_disposed || _state == s) return;
    _state = s;
    if (s != PiServerState.error) _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    debugPrint('PiFrameServer: $message');
    if (_disposed) return;
    _errorMessage = message;
    _state = PiServerState.error;
    notifyListeners();
  }
}
