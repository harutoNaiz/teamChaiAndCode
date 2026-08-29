package com.example.team_chai_and_code

import android.content.Context
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder

/** Generates normalized text embeddings entirely on the device. */
class LocalTextEmbedder(context: Context) : AutoCloseable {
    private val appContext = context.applicationContext
    private val lazyEmbedder = lazy {
        val options = TextEmbedder.TextEmbedderOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(MODEL_ASSET)
                    .build()
            )
            .setL2Normalize(true)
            .build()
        TextEmbedder.createFromOptions(appContext, options)
    }

    fun embed(text: String): FloatArray {
        require(text.isNotBlank()) { "text must not be blank" }
        val result = lazyEmbedder.value.embed(text)
        val embedding = result.embeddingResult().embeddings().firstOrNull()
            ?: throw IllegalStateException("The text embedder returned no embedding")
        return embedding.floatEmbedding()
    }

    override fun close() {
        if (lazyEmbedder.isInitialized()) {
            lazyEmbedder.value.close()
        }
    }

    private companion object {
        const val MODEL_ASSET = "universal_sentence_encoder.tflite"
    }
}
