package com.example.test_app_1

import android.os.Handler
import android.os.Looper
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
}
