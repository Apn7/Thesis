package com.example.test_app_1

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.test_app_1/llm"
        private const val KEYS_CHANNEL = "com.example.test_app_1/hardware_keys"

        // Path inside the APK's asset folder where Flutter bundles assets.
        private const val MODEL_ASSET_PATH =
            "flutter_assets/assets/models/gemma-4-E2B-it.litertlm"

        // Filename used when the model is stored on-device.
        private const val MODEL_FILENAME = "gemma-4-E2B-it.litertlm"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // Engine is long-lived (holds model weights in memory).
    // Conversation is recreated per command — keeps context clean for
    // stateless intent classification.
    private var engine: Engine? = null
    private var systemInstruction: String = ""

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── initialize ────────────────────────────────────────
                    // Called once from SplashScreen.
                    // Copies the model to filesDir on first launch (skips on
                    // subsequent launches), then loads it into the Engine.
                    "initialize" -> {
                        systemInstruction =
                            call.argument<String>("systemInstruction") ?: ""
                        Thread {
                            try {
                                val modelPath = ensureModelFile()
                                val cfg = EngineConfig(
                                    modelPath = modelPath,
                                    // Prefer GPU; LiteRT-LM auto-falls back to
                                    // CPU on devices that don't support it.
                                    backend = Backend.GPU(),
                                )
                                engine?.close()
                                engine = Engine(cfg).also { it.initialize() }
                                mainHandler.post { result.success(null) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("INIT_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }

                    // ── processCommand ────────────────────────────────────
                    // Receives the user's transcribed text.  Creates a fresh
                    // Conversation (so history never accumulates), injects the
                    // system instruction, runs blocking inference, returns the
                    // raw model output string.
                    "processCommand" -> {
                        val text = call.argument<String>("text") ?: ""
                        val eng = engine
                        if (eng == null) {
                            result.error(
                                "NOT_INITIALIZED",
                                "LLM engine not initialized",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val convConfig = ConversationConfig(
                                    systemInstruction = Contents.of(systemInstruction),
                                )
                                val message = eng.createConversation(convConfig).use { conv ->
                                    conv.sendMessage(Contents.of(Content.Text(text)))
                                }
                                // Contents.toString() joins all text parts into one string.
                                val response = message?.contents?.toString() ?: ""
                                mainHandler.post { result.success(response) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error(
                                        "INFERENCE_ERROR",
                                        e.message,
                                        null,
                                    )
                                }
                            }
                        }.start()
                    }

                    // ── dispose ───────────────────────────────────────────
                    "dispose" -> {
                        engine?.close()
                        engine = null
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    /**
     * Ensures the .litertlm model file is present in [filesDir].
     *
     * On first launch this copies ~2.58 GB from the APK asset stream —
     * subsequent launches find the file already there and return immediately.
     *
     * Returns the absolute path of the on-device model file.
     */
    private fun ensureModelFile(): String {
        val dest = File(filesDir, MODEL_FILENAME)
        if (dest.exists() && dest.length() > 1_000_000L) {
            // File already extracted — skip copy.
            return dest.absolutePath
        }

        // Copy from APK assets to writable storage.
        // Use a 4 MB buffer to keep memory pressure low during the large copy.
        assets.open(MODEL_ASSET_PATH).use { input ->
            FileOutputStream(dest).use { output ->
                input.copyTo(output, bufferSize = 4 * 1024 * 1024)
            }
        }
        return dest.absolutePath
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
