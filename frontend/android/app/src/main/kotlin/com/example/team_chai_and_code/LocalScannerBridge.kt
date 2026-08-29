package com.example.team_chai_and_code

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class LocalScannerBridge(
    private val appContext: Context,
    private val activity: Activity?,
    private val indexBridge: AppSearchIndexBridge
) : MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {

    constructor(activity: Activity, indexBridge: AppSearchIndexBridge) :
        this(activity.applicationContext, activity, indexBridge)

    constructor(context: Context, indexBridge: AppSearchIndexBridge) :
        this(context.applicationContext, null, indexBridge)

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var pendingRequestCode: Int = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> {
                val host = activity ?: run {
                    result.error("activity_unavailable", "Folder picker requires a foreground activity", null)
                    return
                }
                pendingResult = result
                pendingRequestCode = REQUEST_CODE_PICK_FOLDER
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
                host.startActivityForResult(intent, REQUEST_CODE_PICK_FOLDER)
            }
            "pickDocument" -> {
                val host = activity ?: run {
                    result.error("activity_unavailable", "Document picker requires a foreground activity", null)
                    return
                }
                pendingResult = result
                pendingRequestCode = REQUEST_CODE_PICK_DOCUMENT
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf("image/*", "application/pdf", "text/plain", "text/markdown")
                    )
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
                host.startActivityForResult(intent, REQUEST_CODE_PICK_DOCUMENT)
            }
            "scanUri" -> {
                val uriString = call.argument<String>("uri")
                if (uriString.isNullOrBlank()) {
                    result.error("invalid_argument", "uri is required", null)
                    return
                }
                executor.execute {
                    try {
                        val scanResults = scanAndIndexUri(Uri.parse(uriString))
                        mainHandler.post { result.success(scanResults) }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("scan_error", e.message ?: "Failed to scan URI", null)
                        }
                    }
                }
            }
            "scanPersisted" -> executor.execute {
                try {
                    val scanResults = scanPersistedSources()
                    mainHandler.post { result.success(scanResults) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("scan_error", e.message, null) }
                }
            }
            "openUri" -> {
                val uriString = call.argument<String>("uri")
                if (uriString.isNullOrBlank()) {
                    result.error("invalid_argument", "uri is required", null)
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse(uriString)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    (activity ?: appContext).startActivity(intent)
                    result.success(mapOf("opened" to true, "uri" to uriString))
                } catch (e: Exception) {
                    result.error("open_error", "Cannot open source URI: ${e.message}", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != pendingRequestCode || pendingResult == null) {
            return false
        }
        val currentResult = pendingResult!!
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            currentResult.success(mapOf("status" to "cancelled"))
            return true
        }

        val uri = data.data!!
        try {
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            appContext.contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (_: Exception) {
            // Some providers don't support persistable flags
        }

        executor.execute {
            try {
                val scanResults = scanAndIndexUri(uri)
                mainHandler.post {
                    currentResult.success(
                        mapOf(
                            "status" to "success",
                            "uri" to uri.toString(),
                            "records" to scanResults
                        )
                    )
                }
            } catch (e: Exception) {
                mainHandler.post {
                    currentResult.error("scan_error", e.message ?: "Failed to scan selected source", null)
                }
            }
        }
        return true
    }

    fun scanPersistedSources(): List<Map<String, Any?>> =
        appContext.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .flatMap { permission -> scanAndIndexUri(permission.uri) }

    fun scanAndIndexUri(uri: Uri): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val contentResolver = appContext.contentResolver

        if (DocumentsContract.isTreeUri(uri)) {
            scanTree(uri, DocumentsContract.getTreeDocumentId(uri), results)
        } else {
            // Single document
            var displayName = "document"
            var mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
            var lastModified = System.currentTimeMillis()

            var cursor: Cursor? = null
            try {
                cursor = contentResolver.query(uri, null, null, null, null)
                if (cursor != null && cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) displayName = cursor.getString(nameIndex) ?: displayName
                }
            } finally {
                cursor?.close()
            }

            results.addAll(processDocument(uri, displayName, mimeType, lastModified))
        }

        return results
    }

    private fun scanTree(
        treeUri: Uri,
        parentDocumentId: String,
        results: MutableList<Map<String, Any?>>,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        appContext.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(0)
                val displayName = cursor.getString(1) ?: "unnamed_document"
                val mimeType = cursor.getString(2) ?: "application/octet-stream"
                val modifiedAt = cursor.getLong(3)
                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    scanTree(treeUri, documentId, results)
                } else {
                    val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                    results.addAll(processDocument(documentUri, displayName, mimeType, modifiedAt))
                }
            }
        }
    }

    private fun processDocument(
        uri: Uri,
        displayName: String,
        mimeType: String,
        lastModified: Long
    ): List<Map<String, Any?>> {
        val records = mutableListOf<Map<String, Any?>>()
        val contentResolver = appContext.contentResolver

        if (mimeType.startsWith("image/")) {
            // Image OCR
            val bytes = readBytes(uri) ?: return emptyList()
            val text = runLocalOcr(bytes)
            if (text.isNotBlank()) {
                val recordId = sha256("$uri|$lastModified|$text")
                val recordMap = mapOf(
                    "id" to recordId,
                    "source_uri" to uri.toString(),
                    "display_name" to displayName,
                    "mime_type" to mimeType,
                    "content_type" to "image_ocr",
                    "transcription" to text,
                    "modified_at" to if (lastModified > 0) lastModified else System.currentTimeMillis()
                )
                // Upsert directly into AppSearch index
                indexBridge.indexDirectly(recordMap, "image_ocr")
                records.add(recordMap)
            }
        } else if (mimeType == "application/pdf") {
            // PDF extraction / page OCR
            records.addAll(processPdf(uri, displayName, lastModified))
        } else if (mimeType.startsWith("text/")) {
            val bytes = readBytes(uri) ?: return emptyList()
            val text = String(bytes, Charsets.UTF_8).trim()
            if (text.isNotBlank()) {
                val recordId = sha256("$uri|$lastModified|$text")
                val recordMap = mapOf(
                    "id" to recordId,
                    "source_uri" to uri.toString(),
                    "display_name" to displayName,
                    "mime_type" to mimeType,
                    "content_type" to "text",
                    "transcription" to text,
                    "modified_at" to if (lastModified > 0) lastModified else System.currentTimeMillis()
                )
                indexBridge.indexDirectly(recordMap, "text")
                records.add(recordMap)
            }
        }
        return records
    }

    private fun processPdf(uri: Uri, displayName: String, lastModified: Long): List<Map<String, Any?>> {
        val records = mutableListOf<Map<String, Any?>>()
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        try {
            pfd = appContext.contentResolver.openFileDescriptor(uri, "r")
            if (pfd != null) {
                renderer = PdfRenderer(pfd)
                val pageCount = renderer.pageCount
                for (pageIndex in 0 until pageCount) {
                    val pageNum = pageIndex + 1
                    val page = renderer.openPage(pageIndex)
                    // Render page bitmap for OCR
                    val bitmap = android.graphics.Bitmap.createBitmap(
                        page.width,
                        page.height,
                        android.graphics.Bitmap.Config.ARGB_8888
                    )
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    page.close()

                    val stream = ByteArrayOutputStream()
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                    val pageBytes = stream.toByteArray()
                    val pageText = runLocalOcr(pageBytes)

                    if (pageText.isNotBlank()) {
                        val recordId = sha256("$uri|page:$pageNum|$lastModified")
                        val recordMap = mapOf(
                            "id" to recordId,
                            "source_uri" to uri.toString(),
                            "display_name" to displayName,
                            "mime_type" to "application/pdf",
                            "content_type" to "pdf_ocr",
                            "page" to pageNum,
                            "transcription" to pageText,
                            "modified_at" to if (lastModified > 0) lastModified else System.currentTimeMillis()
                        )
                        indexBridge.indexDirectly(recordMap, "image_ocr")
                        records.add(recordMap)
                    }
                }
            }
        } catch (_: Exception) {
            // Do not derive faux text from PDF binary data. Native text/PDF OCR
            // must be implemented by a real local extractor before indexing.
            return emptyList()
        } finally {
            renderer?.close()
            pfd?.close()
        }
        return records
    }

    private fun readBytes(uri: Uri): ByteArray? {
        return try {
            appContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    private fun runLocalOcr(bytes: ByteArray): String {
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("OCR source is not a decodable image")
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        return try {
            val result = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)))
            result.text.trim().also { require(it.isNotEmpty()) { "OCR returned empty text" } }
        } finally {
            recognizer.close()
        }
    }

    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    companion object {
        const val REQUEST_CODE_PICK_FOLDER = 2001
        const val REQUEST_CODE_PICK_DOCUMENT = 2002
    }
}
