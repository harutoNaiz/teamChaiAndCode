package com.example.team_chai_and_code

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Native LiteRT-LM bridge used by Flutter for downloaded .litertlm models. */
class LocalModelBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var loadedPath: String? = null
    private var engine: Engine? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "generate") {
            result.notImplemented()
            return
        }
        val modelPath = call.argument<String>("modelPath")
        val prompt = call.argument<String>("prompt")
        val maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 512
        val enableThinking = call.argument<Boolean>("enableThinking") ?: false
        if (modelPath.isNullOrBlank() || prompt.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "modelPath and prompt are required", null)
            return
        }
        executor.execute {
            try {
                val file = File(modelPath)
                require(file.isFile && file.length() > 1024) {
                    "Local model file is missing or incomplete: $modelPath"
                }
                val conversationEngine = ensureEngine(modelPath)
                conversationEngine.createConversation().use { conversation ->
                    val response = conversation.sendMessage(
                        prompt,
                        // Qwen3 exposes this template variable to skip its
                        // expensive visible thinking phase for normal chat.
                        extraContext = mapOf("enable_thinking" to enableThinking),
                        maxOutputToken = maxOutputTokens.coerceIn(1, 2048),
                    )
                    result.success(mapOf("text" to response.toString()))
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Local LiteRT-LM inference failed", error)
                result.error("INFERENCE_FAILED", error.message ?: error.javaClass.simpleName, null)
            }
        }
    }

    @Synchronized
    private fun ensureEngine(modelPath: String): Engine {
        if (loadedPath == modelPath && engine != null) return engine!!
        engine?.close()
        // CPU is the portable baseline. The LiteRT-LM package can be switched
        // to GPU/NPU once the target phone's delegate libraries are bundled.
        val config = EngineConfig(
            modelPath = modelPath,
            backend = Backend.CPU(),
            cacheDir = context.cacheDir.absolutePath,
        )
        return Engine(config).also {
            it.initialize()
            engine = it
            loadedPath = modelPath
        }
    }

    fun close() {
        executor.shutdownNow()
        synchronized(this) {
            engine?.close()
            engine = null
            loadedPath = null
        }
    }

    companion object {
        private const val TAG = "LocalModelBridge"
    }
}
