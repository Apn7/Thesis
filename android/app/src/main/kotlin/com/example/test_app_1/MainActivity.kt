package com.example.test_app_1

import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
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
