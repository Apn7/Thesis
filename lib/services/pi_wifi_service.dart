import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/constants.dart';

/// Connection states for the cane's own WiFi access point.
enum PiWifiState { idle, requesting, connected, lost, failed, wifiOff }

/// Joins the Pi's access point ([AppConstants.piApSsid]) using Android's
/// Wi-Fi Network Request API (`WifiNetworkSpecifier`) — the OS mechanism for
/// peer-to-peer links to IoT devices like cameras.
///
/// This single link carries the **whole cane system** — camera frames
/// (`piFramePort`) and sonar distance (`piDistancePort`) both ride it.
///
/// The link is **app-scoped and local-only**: the native side strips
/// `NET_CAPABILITY_INTERNET` from the request, so ConnectivityService never
/// elects the Pi network as the phone's default route. Internet traffic
/// (Groq, geocoding) keeps flowing over mobile data, unlike a manual join
/// from Settings which hijacks the default route. Inbound frame/sonar
/// sockets need no special binding — the existing `ServerSocket`s receive
/// the Pi's connections over this link as-is.
///
/// **Persistent, process-scoped request:** [connect] registers ONE request
/// with no timeout and resolves as soon as it's registered. The native side
/// holds it at **process scope** (not the Activity), so the cane link survives
/// screen-off, Activity re-creation and app re-entry — the foreground service
/// keeps the process alive and the link stays up while the phone is pocketed.
/// Re-opening the app re-syncs to the live link instead of re-joining, so
/// there is no second consent prompt and no reconnection lag. From then on the
/// OS itself joins the cane the moment its AP appears in any scan — app opened
/// before the cane powered on "just works" with zero taps. While searching,
/// a periodic scan nudge keeps discovery in the seconds range. Connection
/// state arrives via native events (`onPiWifiAvailable`/`Unavailable`/
/// `Lost`); `Unavailable` can only mean the user declined the consent
/// dialog. That dialog is an Android security boundary (no app may silently
/// join a phone to a network) and appears exactly once per phone — the
/// approval is persisted here so callers can speak guidance beforehand on
/// the first launch only. Android 10+; other platforms fail cleanly.
class PiWifiService extends ChangeNotifier {
  PiWifiService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static final PiWifiService instance = PiWifiService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.test_app_1/pi_wifi',
  );

  /// Persisted after the first successful join: the one-time system consent
  /// has been granted, so every future request is silent.
  static const String _pairedPrefKey = 'pi_wifi_paired_once';

  PiWifiState _state = PiWifiState.idle;
  PiWifiState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Non-null while the join is stuck AND the phone is associated to some
  /// other WiFi network (e.g. home WiFi). On most phones Android refuses to
  /// *silently* drop an internet-bearing WiFi for the cane's local-only link
  /// (AOSP revokes the remembered approval unless the radio can run a second
  /// station interface), so this state needs a spoken nudge: a consent window
  /// will appear and the user must press Connect once.
  String? _blockingWifiSsid;
  String? get blockingWifiSsid => _blockingWifiSsid;

  bool _autoJoin = false;
  Timer? _retryTimer;
  Timer? _scanTimer;
  Timer? _watchdogTimer;

  /// True once the cane link has connected at least once this process.
  /// Splits behaviour into two phases:
  ///  * **Acquisition** (`false`): fight to win the radio off home WiFi —
  ///    the re-file watchdog is allowed to run.
  ///  * **Maintenance** (`true`): a live link exists (or briefly dropped and
  ///    the OS's persistent request is auto-re-healing it). The watchdog is
  ///    permanently disarmed — re-filing tears the link down and re-registers
  ///    it, which on a marginally flaky AP turns a self-healing blip into a
  ///    thrash of drops and latency spikes. This is the regression that made
  ///    the Pi-AP link feel worse than the old hotspot/debug path; once
  ///    connected we trust the OS to hold/recover the link and stay quiet.
  bool _hasConnectedOnce = false;

  /// Whether this phone has been through the one-time consent dialog before.
  /// Lets the UI speak "a permission window is about to appear" guidance on
  /// the very first launch and stay silent forever after.
  Future<bool> hasPairedBefore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_pairedPrefKey) ?? false;
    } on Exception {
      return false;
    }
  }

  Future<void> _markPaired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pairedPrefKey, true);
    } on Exception catch (e) {
      debugPrint('PiWifiService: could not persist pairing flag — $e');
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPiWifiAvailable':
        _stopScanNudger();
        _stopWatchdog();
        _hasConnectedOnce = true;
        _blockingWifiSsid = null;
        _state = PiWifiState.connected;
        _errorMessage = null;
        notifyListeners();
        _markPaired();
      case 'onPiWifiUnavailable':
        // No timeout on the request, so this only means the user declined
        // the consent dialog. Retry slowly — a decline must not turn into
        // dialog spam for a blind user.
        _stopScanNudger();
        _stopWatchdog();
        _state = PiWifiState.failed;
        _errorMessage = 'Connection request declined';
        notifyListeners();
        if (_autoJoin) _scheduleRetry(const Duration(seconds: 60));
      case 'onPiWifiLost':
        // Cane rebooted / briefly out of range. The persistent request stays
        // registered on the native side, so the OS re-associates on its own
        // when the AP returns — and the WifiLock keeps the radio hot so that
        // re-heal is fast. We deliberately do NOT re-file or hammer scans
        // here: this is the maintenance phase (we've connected before), and
        // re-filing would force a hard down/up that destabilises a flaky link
        // instead of letting it recover. Just mirror the state for the UI.
        _stopScanNudger();
        _stopWatchdog();
        _state = PiWifiState.lost;
        notifyListeners();
    }
  }

  /// Keeps the cane link up hands-free for the rest of the session (until
  /// [disableAutoJoin]). Safe to call repeatedly.
  void enableAutoJoin() {
    if (_autoJoin) return;
    _autoJoin = true;
    _maintain();
  }

  void disableAutoJoin() {
    _autoJoin = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stopScanNudger();
    _stopWatchdog();
  }

  Future<void> _maintain() async {
    if (!_autoJoin ||
        _state == PiWifiState.connected ||
        _state == PiWifiState.requesting) {
      return;
    }
    // The one failure only the user can fix: the WiFi toggle is off. Surface
    // it as a distinct state so the UI/TTS can guide them, and poll for the
    // toggle coming back — a request registered with WiFi off goes nowhere.
    final wifiOn = await isWifiEnabled();
    if (!_autoJoin) return;
    if (!wifiOn) {
      if (_state != PiWifiState.wifiOff) {
        _state = PiWifiState.wifiOff;
        notifyListeners();
      }
      _scheduleRetry(const Duration(seconds: 15));
      return;
    }
    final registered = await connect();
    if (!_autoJoin) return;
    // Once registered there is nothing to poll: the OS holds the request
    // open and the native events drive every later transition.
    if (!registered) _scheduleRetry(const Duration(seconds: 30));
  }

  void _scheduleRetry(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _maintain);
  }

  // While a request is searching, kick a WiFi scan periodically so a cane
  // powered on mid-session is found in seconds, not at the OS's next lazy
  // background scan. Best-effort: the OS throttles scans (~4 per 2 min) and
  // the pending request connects on background scans regardless. The first
  // nudge fires almost immediately so a cane already beaconing at app launch
  // is found on the very first sweep.
  void _startScanNudger() {
    _scanTimer?.cancel();
    Timer(const Duration(seconds: 3), () async {
      if (_state != PiWifiState.requesting) return;
      try {
        await _channel.invokeMethod('nudgeScan');
      } on Exception {
        // Throttled or unsupported — background scans still cover us.
      }
    });
    _scanTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (_state != PiWifiState.requesting) return;
      try {
        await _channel.invokeMethod('nudgeScan');
      } on Exception {
        // Throttled or unsupported — background scans still cover us.
      }
    });
  }

  void _stopScanNudger() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  // ── Stuck-join escalation watchdog ──────────────────────────────────────
  //
  // A specifier request is only *evaluated* by Android when it is freshly
  // filed: on Android 12/13 the OS revokes the remembered silent approval
  // whenever the phone is already associated to another WiFi and the radio
  // cannot host a second station interface (AOSP WifiNetworkFactory —
  // "escalate and display the dialog to the user EVEN if we have a normal
  // bypass"), and some OEM builds simply wedge a long-lived unfulfilled
  // request. So a request registered once and left alone can sit in
  // `requesting` forever while the phone stays glued to home WiFi.
  //
  // The watchdog makes the cane CONTEST that: while the state stays
  // `requesting`, every [AppConstants.piWifiRefileSeconds] it re-files the
  // request natively (drop + fresh register). Each re-file restarts the
  // platform's own periodic scans with an immediate sweep and forces a fresh
  // connect-or-consent decision — either the OS joins the cane silently, or
  // it re-surfaces the consent window for the user to press Connect. It also
  // records which WiFi is hogging the radio ([blockingWifiSsid]) so the UI
  // can speak targeted guidance instead of searching in silence.
  //
  // Deliberately does NOT run before the first-ever pairing (re-filing
  // dismisses a visible consent dialog, and the first launch is exactly when
  // a blind user is being talked through it) NOR after the link has connected
  // once this process ([_hasConnectedOnce]) — post-connect re-filing is the
  // thrash that destabilised the live link.
  void _startWatchdog() {
    if (_hasConnectedOnce) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(
      Duration(seconds: AppConstants.piWifiRefileSeconds),
      (_) => _watchdogTick(),
    );
  }

  Future<void> _watchdogTick() async {
    // Belt-and-braces: never re-file once a link has existed, even if a
    // stale timer somehow survives.
    if (_hasConnectedOnce) {
      _stopWatchdog();
      return;
    }
    if (!_autoJoin || _state != PiWifiState.requesting) return;
    if (!await hasPairedBefore()) return;
    if (_hasConnectedOnce || !_autoJoin || _state != PiWifiState.requesting) {
      return;
    }
    // Surface who is blocking the radio (null = no WiFi associated, i.e.
    // the cane is probably just not in range yet).
    String? blocker;
    try {
      blocker = await _channel.invokeMethod<String>('getCurrentWifiSsid');
    } on Exception {
      blocker = null;
    }
    if (blocker == AppConstants.piApSsid) return; // join is completing
    if (blocker != _blockingWifiSsid) {
      _blockingWifiSsid = blocker;
      notifyListeners();
    }
    try {
      await _channel.invokeMethod<bool>('refreshNetwork', {
        'ssid': AppConstants.piApSsid,
        'psk': AppConstants.piApPsk,
      });
      debugPrint(
        'PiWifiService: re-filed join request '
        '(blocking WiFi: ${blocker ?? "none"})',
      );
    } on Exception catch (e) {
      debugPrint('PiWifiService: refreshNetwork failed — $e');
    }
    // Give the fresh request a prompt first sweep too.
    try {
      await _channel.invokeMethod('nudgeScan');
    } on Exception {
      // Best-effort.
    }
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Whether the phone's WiFi radio is on (Android). Errs on `true` so a
  /// probe failure falls through to [connect], which reports real errors.
  Future<bool> isWifiEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isWifiEnabled') ?? true;
    } on Exception {
      return true;
    }
  }

  /// Registers the persistent join request with the OS. Resolves when the
  /// request is REGISTERED (not yet connected) — from then on the OS joins
  /// the cane whenever its AP is in range and [state] follows the native
  /// events. Returns false only if registration itself failed.
  Future<bool> connect() async {
    if (_state == PiWifiState.requesting || _state == PiWifiState.connected) {
      return true;
    }
    _state = PiWifiState.requesting;
    _errorMessage = null;
    notifyListeners();
    try {
      await _channel.invokeMethod<bool>('requestNetwork', {
        'ssid': AppConstants.piApSsid,
        'psk': AppConstants.piApPsk,
      });
      _startScanNudger();
      _startWatchdog();
      return true;
    } on PlatformException catch (e) {
      debugPrint('PiWifiService: request failed — ${e.code}: ${e.message}');
      _state = PiWifiState.failed;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } on MissingPluginException {
      debugPrint('PiWifiService: pi_wifi channel unavailable (not Android)');
      _state = PiWifiState.failed;
      _errorMessage = 'Unsupported platform';
      notifyListeners();
      return false;
    }
  }

  /// Drops the app-scoped link by releasing the network request (and the
  /// WifiLock, native-side). Resets to the acquisition phase so a later
  /// [connect] fights for the radio again.
  Future<void> release() async {
    _stopScanNudger();
    _stopWatchdog();
    _hasConnectedOnce = false;
    _blockingWifiSsid = null;
    try {
      await _channel.invokeMethod('releaseNetwork');
    } on Exception catch (e) {
      debugPrint('PiWifiService: release failed — $e');
    }
    _state = PiWifiState.idle;
    _errorMessage = null;
    notifyListeners();
  }
}
