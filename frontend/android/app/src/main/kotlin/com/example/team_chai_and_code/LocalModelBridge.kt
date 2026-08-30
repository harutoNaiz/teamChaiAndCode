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
        engine = null
        loadedPath = null
        // Prefer the Adreno GPU: prefill and decode are markedly faster than the
        // CPU baseline on capable hardware (e.g. Snapdragon 8 Elite). Fall back
        // to CPU if the GPU delegate or this model bundle can't initialise, so
        // the assistant still runs everywhere. (NPU/Hexagon would be faster
        // still but needs the QNN delegate .so bundled in the APK.)
        val backends = listOf("GPU" to Backend.GPU(), "CPU" to Backend.CPU())
        var lastError: Throwable? = null
        for ((name, backend) in backends) {
            try {
                val started = System.currentTimeMillis()
                val candidate = Engine(
                    EngineConfig(
                        modelPath = modelPath,
                        backend = backend,
                        cacheDir = context.cacheDir.absolutePath,
                    )
                )
                candidate.initialize()
                engine = candidate
                loadedPath = modelPath
                Log.i(TAG, "LiteRT-LM engine ready on $name backend in ${System.currentTimeMillis() - started}ms")
                return candidate
            } catch (error: Throwable) {
                lastError = error
                Log.w(TAG, "LiteRT-LM init failed on $name backend: ${error.message}")
            }
        }
        throw lastError ?: IllegalStateException("Unable to initialise LiteRT-LM engine")
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
