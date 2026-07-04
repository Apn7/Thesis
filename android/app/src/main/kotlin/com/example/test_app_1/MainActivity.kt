package com.example.test_app_1

import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.view.KeyEvent
import androidx.annotation.RequiresApi
// LiteRT-LM (on-device Gemma LLM) is disabled: its AAR bundles libLiteRt.so,
// which collides with the LiteRT runtime shipped by the ultralytics_yolo
// vision plugin at the mergeDebugNativeLibs step.  The LLM is feature-flagged
// off (AppConstants.enableLlm = false) and its 2.58 GB model asset is not
// bundled, so nothing functional is lost.  To re-enable: restore these
// imports, the engine code below, and the litertlm-android dependency in
// app/build.gradle.kts — then resolve the duplicate-.so conflict (align the
// LiteRT versions or scope a packaging pickFirst to the matching runtime).
// import com.google.ai.edge.litertlm.Backend
// import com.google.ai.edge.litertlm.Content
// import com.google.ai.edge.litertlm.Contents
// import com.google.ai.edge.litertlm.ConversationConfig
// import com.google.ai.edge.litertlm.Engine
// import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.test_app_1/llm"
        private const val KEYS_CHANNEL = "com.example.test_app_1/hardware_keys"
        private const val SMS_CHANNEL = "com.example.test_app_1/sms"
        private const val FGS_CHANNEL = "com.example.test_app_1/foreground_service"
        private const val SYSTEM_CHANNEL = "com.example.test_app_1/system"
        private const val PI_WIFI_CHANNEL = "com.example.test_app_1/pi_wifi"

        // Pi camera WiFi link, held at PROCESS scope (companion) — NOT on the
        // Activity — so the cane connection survives Activity teardown, engine
        // re-creation and screen-off (the foreground service keeps the process
        // alive). Only releaseNetwork() or process death drops it. A non-null
        // callback means a request is registered; `piWifiChannel` always points
        // at the currently-attached engine's channel so events reach live Dart.
        private val piWifiMainHandler = Handler(Looper.getMainLooper())
        private var piWifiChannel: MethodChannel? = null
        private var piWifiCallback: ConnectivityManager.NetworkCallback? = null
        private var piWifiConnected = false
    }

    // Channel used to forward consumed hardware-key events (volume up) to Dart.
    private var keysChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Force the app's audio (TTS playback + STT recognizer prompt sounds)
        // to maximum loudness — accessibility requirement for visually
        // impaired users who rely on audio feedback.
        maxOutMediaVolume()

        keysChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KEYS_CHANNEL,
        )

        // LLM channel stub — LiteRT-LM is disabled (see imports note above).
        // Keeps the channel alive so the Dart side gets a clean, identifiable
        // error instead of MissingPluginException if it ever calls in while
        // the feature flag is off.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize", "processCommand" -> result.error(
                        "LLM_DISABLED",
                        "On-device LLM is disabled in this build " +
                            "(LiteRT-LM removed to avoid native-lib conflict " +
                            "with the vision plugin).",
                        null,
                    )
                    "dispose" -> result.success(null)
                    else -> result.notImplemented()
                }
            }

        // Emergency SOS: send an SMS directly via SmsManager (zero-tap,
        // hands-free — the whole point for a blind user). The Dart side
        // requests SEND_SMS at runtime before calling; we re-check here and
        // fail cleanly if it was denied. Multipart-aware so the bilingual
        // Bengali message + maps link (which spans several 70-char Unicode
        // segments) is delivered as one logical message.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val addresses = call.argument<List<String>>("addresses")
                        val message = call.argument<String>("message")
                        if (addresses.isNullOrEmpty() || message.isNullOrEmpty()) {
                            result.error(
                                "BAD_ARGS",
                                "addresses and message are required",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        if (checkSelfPermission(android.Manifest.permission.SEND_SMS)
                            != PackageManager.PERMISSION_GRANTED
                        ) {
                            result.error(
                                "NO_PERMISSION",
                                "SEND_SMS permission not granted",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val sms = smsManager()
                            var sent = 0
                            for (addr in addresses) {
                                val parts = sms.divideMessage(message)
                                sms.sendMultipartTextMessage(
                                    addr, null, parts, null, null,
                                )
                                sent++
                            }
                            result.success(sent)
                        } catch (e: Exception) {
                            result.error("SEND_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Foreground service: keeps the cane link (TCP servers + YOLO + alerts)
        // alive while the phone is pocketed with the screen off. The Dart side
        // starts it when the fusion/distance pipeline starts and stops it when
        // that pipeline stops — the service holds no logic of its own.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            CaneForegroundService.start(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FGS_START_FAILED", e.message, null)
                        }
                    }
                    "stop" -> {
                        try {
                            CaneForegroundService.stop(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FGS_STOP_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // System info: the phone's real battery level, spoken by the voice
        // assistant. BatteryManager needs no permission.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatteryLevel" -> {
                        try {
                            val bm = getSystemService(Context.BATTERY_SERVICE)
                                as BatteryManager
                            result.success(
                                bm.getIntProperty(
                                    BatteryManager.BATTERY_PROPERTY_CAPACITY,
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("BATTERY_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Pi camera WiFi: join the cane's own access point through the
        // Wi-Fi Network Request API (WifiNetworkSpecifier). The request
        // deliberately strips NET_CAPABILITY_INTERNET, so ConnectivityService
        // never elects this link as the default route — every other socket
        // in the phone (Groq, geocoding) keeps riding mobile data. This is
        // the crucial difference from a manual Settings join, which makes
        // the internet-less Pi network the default route and strands the
        // phone offline. We also never bind the process to this network;
        // the app's inbound frame/sonar ServerSockets receive the Pi's
        // connections over it without any binding.
        piWifiChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PI_WIFI_CHANNEL,
        )
        piWifiChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNetwork" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.error(
                            "UNSUPPORTED",
                            "WifiNetworkSpecifier requires Android 10+",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    val ssid = call.argument<String>("ssid")
                    val psk = call.argument<String>("psk")
                    if (ssid.isNullOrEmpty() || psk.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "ssid and psk are required", null)
                        return@setMethodCallHandler
                    }
                    requestPiNetwork(ssid, psk, result)
                }
                "releaseNetwork" -> {
                    releasePiNetwork()
                    result.success(true)
                }
                "isWifiEnabled" -> {
                    try {
                        val wm = applicationContext
                            .getSystemService(Context.WIFI_SERVICE) as WifiManager
                        result.success(wm.isWifiEnabled)
                    } catch (e: Exception) {
                        result.error("WIFI_STATE_FAILED", e.message, null)
                    }
                }
                "nudgeScan" -> result.success(nudgeWifiScan())
                else -> result.notImplemented()
            }
        }
    }

    // ── Pi camera WiFi (WifiNetworkSpecifier) ────────────────────────────────

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun requestPiNetwork(
        ssid: String,
        psk: String,
        result: MethodChannel.Result,
    ) {
        // Already registered? Then the OS-level request outlived a previous
        // Activity/engine (kept alive by the foreground service across
        // screen-off / re-entry). Don't register a second one — just re-sync
        // the freshly-attached Dart side to the real link state so a returning
        // user sees "connected" with no second consent prompt.
        if (piWifiCallback != null) {
            if (piWifiConnected) piWifiChannel?.invokeMethod("onPiWifiAvailable", null)
            result.success(true)
            return
        }

        val cm = applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(psk)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                piWifiMainHandler.post {
                    piWifiConnected = true
                    piWifiChannel?.invokeMethod("onPiWifiAvailable", null)
                }
            }

            override fun onUnavailable() {
                // With no timeout on the request this only fires when the
                // user declines the consent dialog. The OS auto-unregisters
                // the request here.
                piWifiMainHandler.post {
                    piWifiConnected = false
                    piWifiCallback = null
                    piWifiChannel?.invokeMethod("onPiWifiUnavailable", null)
                }
            }

            override fun onLost(network: Network) {
                // Pi rebooted / out of range. The persistent request stays
                // registered and the OS re-associates when the AP returns;
                // just tell Dart so its state/UI follows.
                piWifiMainHandler.post {
                    piWifiConnected = false
                    piWifiChannel?.invokeMethod("onPiWifiLost", null)
                }
            }
        }
        try {
            // PERSISTENT request — deliberately no timeout, registered on the
            // APPLICATION context so it survives Activity teardown. It stays
            // registered until releaseNetwork() or process death, so the OS
            // joins the cane the moment its AP appears (even minutes after
            // launch, no re-prompt — the first approval is remembered) and the
            // link keeps flowing while the phone is pocketed. The channel
            // result only means "request registered"; connection state flows
            // back through the onPiWifi* events above.
            cm.requestNetwork(request, cb)
            piWifiCallback = cb
            result.success(true)
        } catch (e: Exception) {
            piWifiCallback = null
            result.error("REQUEST_FAILED", e.message, null)
        }
    }

    /** Best-effort scan kick so a waiting request finds the cane in seconds
     *  instead of at the next lazy background scan. The OS throttles this
     *  (~4 scans / 2 min); failures are irrelevant — the request still
     *  connects on the next background scan either way. */
    private fun nudgeWifiScan(): Boolean =
        try {
            @Suppress("DEPRECATION")
            (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                .startScan()
        } catch (e: Exception) {
            false
        }

    private fun releasePiNetwork() {
        val cb = piWifiCallback ?: return
        piWifiCallback = null
        piWifiConnected = false
        try {
            val cm = applicationContext
                .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(cb)
        } catch (_: Exception) {
            // Already unregistered (e.g. after onUnavailable) — fine.
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // The engine (and its channel) is going away, but the Pi WiFi request
        // is process-scoped and stays registered — drop only the now-dead
        // channel reference so the callback stops pushing into it. The next
        // engine re-syncs through requestNetwork's "already registered" path.
        // Deliberately does NOT release the network: that would defeat the
        // foreground service keeping the cane link up across screen-off.
        piWifiChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Obtain an SmsManager the API-correct way (getDefault is deprecated 31+). */
    private fun smsManager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

    // ── hardware-key interception ─────────────────────────────────────────────
    //
    // Push-to-talk: while the app is in the foreground, holding either
    // Volume-Up or Volume-Down opens the mic; releasing it stops listening.
    // Both keys are fully consumed so the system volume never changes from
    // these presses — TTS/STT loudness is pinned to max separately.
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (isVolumeKey(keyCode)) {
            // Only fire on the initial press, not on auto-repeats while held.
            if (event != null && event.repeatCount == 0) {
                keysChannel?.invokeMethod("onVolumeKeyDown", null)
            }
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (isVolumeKey(keyCode)) {
            keysChannel?.invokeMethod("onVolumeKeyUp", null)
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun isVolumeKey(keyCode: Int): Boolean =
        keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            keyCode == KeyEvent.KEYCODE_VOLUME_DOWN

    // Re-apply max media volume whenever the app comes back to the foreground,
    // so anything the user (or another app) changed in the meantime is reset.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) maxOutMediaVolume()
    }

    /**
     * Pin STREAM_MUSIC (used by flutter_tts and the STT recognizer's prompts)
     * to its maximum value.  Silent — no UI flash, no audible click.
     */
    private fun maxOutMediaVolume() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, max, 0)
        } catch (_: SecurityException) {
            // Some OEMs require Do-Not-Disturb access to change stream volume
            // when DND is active — silently ignore in that edge case.
        }
    }
}
