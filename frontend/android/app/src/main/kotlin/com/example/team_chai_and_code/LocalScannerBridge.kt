package com.example.team_chai_and_code

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
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
    // Durable "already indexed" markers so a refresh skips unchanged files
    // instead of re-reading and re-running OCR on every pass.
    private val seenPrefs =
        appContext.getSharedPreferences("local_scan_seen_v1", Context.MODE_PRIVATE)
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
            // Persist exactly the access flags supplied by DocumentsUI. Using
            // a hard-coded flag and swallowing a failure made a selected tree
            // appear to work once, then disappear on the next refresh/start.
            val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            require(takeFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0) {
                "Folder picker did not grant read access"
            }
            appContext.contentResolver.takePersistableUriPermission(uri, takeFlags)
            require(
                appContext.contentResolver.persistedUriPermissions.any {
                    it.uri == uri && it.isReadPermission
                }
            ) { "Android did not persist read access for the selected folder" }
            Log.i(LOG_TAG, "Persisted folder access uri=$uri")
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Unable to persist folder access uri=$uri", error)
            currentResult.error(
                "folder_permission_not_persisted",
                "Could not retain access to this folder: ${error.message}",
                null,
            )
            return true
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

    fun scanPersistedSources(): List<Map<String, Any?>> {
        val readPermissions = appContext.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
        val results = mutableListOf<Map<String, Any?>>()
        // Ground truth for reconciliation: every file URI actually present in a
        // tree we fully enumerated this pass. Only fully-walked trees are
        // reconcilable -- a failed listing must never read as "files deleted".
        val liveUris = mutableSetOf<String>()
        val reconcilableTrees = mutableListOf<String>()
        for (permission in readPermissions) {
            val uri = permission.uri
            if (DocumentsContract.isTreeUri(uri)) {
                val complete = scanTree(
                    uri, DocumentsContract.getTreeDocumentId(uri), results, liveUris)
                if (complete) reconcilableTrees.add(uri.toString())
            } else {
                liveUris.add(uri.toString())
                results.addAll(scanAndIndexUri(uri))
            }
        }
        // Purge catalog + AppSearch entries for files that vanished from a fully
        // scanned tree (deleted / renamed / moved), then forget their scan
        // markers so a same-named recreation re-indexes cleanly.
        if (reconcilableTrees.isNotEmpty()) {
            val purged = indexBridge.reconcileScannedTrees(reconcilableTrees, liveUris)
            if (purged.isNotEmpty()) {
                val editor = seenPrefs.edit()
                purged.forEach { editor.remove(it) }
                editor.apply()
                Log.i(LOG_TAG, "reconcile purged ${purged.size} stale source(s)")
            }
        }
        return results
    }

    fun scanAndIndexUri(uri: Uri): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val contentResolver = appContext.contentResolver

        if (DocumentsContract.isTreeUri(uri)) {
            scanTree(uri, DocumentsContract.getTreeDocumentId(uri), results, null)
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
        liveUris: MutableSet<String>?,
    ): Boolean {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        // A null cursor / query error is a listing failure, NOT an empty folder.
        // Report it as incomplete so a transient provider hiccup can never make
        // reconciliation purge still-present files.
        val cursor = try {
            appContext.contentResolver.query(childrenUri, projection, null, null, null)
        } catch (error: Exception) {
            Log.w(LOG_TAG, "Child listing failed doc=$parentDocumentId", error)
            return false
        } ?: return false
        var complete = true
        cursor.use { rows ->
            while (rows.moveToNext()) {
                val documentId = rows.getString(0)
                val displayName = rows.getString(1) ?: "unnamed_document"
                val mimeType = rows.getString(2) ?: "application/octet-stream"
                val modifiedAt = rows.getLong(3)
                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    if (!scanTree(treeUri, documentId, results, liveUris)) complete = false
                } else {
                    val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                    // Record presence before extraction so files skipped as
                    // unchanged (or unsupported) still count as live.
                    liveUris?.add(documentUri.toString())
                    results.addAll(processDocument(documentUri, displayName, mimeType, modifiedAt))
                }
            }
        }
        return complete
    }

    private fun processDocument(
        uri: Uri,
        displayName: String,
        mimeType: String,
        lastModified: Long
    ): List<Map<String, Any?>> {
        val records = mutableListOf<Map<String, Any?>>()
        val contentResolver = appContext.contentResolver

        // Skip files already indexed at this modification time. Avoids
        // re-reading bytes and re-running OCR for every persisted-source pass.
        if (isScanSeen(uri, lastModified)) {
            return emptyList()
        }

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
        if (records.isNotEmpty()) {
            markScanSeen(uri, lastModified)
        }
        return records
    }

    private fun processPdf(uri: Uri, displayName: String, lastModified: Long): List<Map<String, Any?>> {
        val embeddedTextRecords = extractPdfTextLayer(uri, displayName, lastModified)
        if (embeddedTextRecords.isNotEmpty()) {
            return embeddedTextRecords
        }

        // A scanned PDF has no text layer. Render each page and use local ML
        // Kit OCR only in that case.
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
                    // Render at 2x native page size. PDF points map to a small
                    // bitmap at 1x and ML Kit commonly returns no text for
                    // normal document-sized fonts at that resolution.
                    val renderedWidth = page.width * PDF_OCR_RENDER_SCALE
                    val renderedHeight = page.height * PDF_OCR_RENDER_SCALE
                    val bitmap = android.graphics.Bitmap.createBitmap(
                        renderedWidth,
                        renderedHeight,
                        android.graphics.Bitmap.Config.ARGB_8888
                    )
                    page.render(
                        bitmap,
                        Rect(0, 0, renderedWidth, renderedHeight),
                        null,
                        PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                    )
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
                        Log.i(LOG_TAG, "Indexed PDF OCR page=$pageNum uri=$uri")
                    } else {
                        Log.w(LOG_TAG, "OCR returned no text for PDF page=$pageNum uri=$uri")
                    }
                }
            }
        } catch (error: Exception) {
            // Never manufacture text from PDF bytes. Report the extraction
            // failure so it is diagnosable instead of silently losing a source.
            Log.e(LOG_TAG, "PDF OCR failed for uri=$uri", error)
        } finally {
            renderer?.close()
            pfd?.close()
        }
        return records
    }

    private fun extractPdfTextLayer(
        uri: Uri,
        displayName: String,
        lastModified: Long,
    ): List<Map<String, Any?>> {
        val records = mutableListOf<Map<String, Any?>>()
        try {
            PDFBoxResourceLoader.init(appContext)
            appContext.contentResolver.openInputStream(uri)?.use { input ->
                PDDocument.load(input).use { document ->
                    val stripper = PDFTextStripper()
                    for (pageNum in 1..document.numberOfPages) {
                        stripper.startPage = pageNum
                        stripper.endPage = pageNum
                        val text = stripper.getText(document).trim()
                        if (text.isBlank()) continue

                        val recordId = sha256("$uri|page:$pageNum|$lastModified")
                        val recordMap = mapOf(
                            "id" to recordId,
                            "source_uri" to uri.toString(),
                            "display_name" to displayName,
                            "mime_type" to "application/pdf",
                            "content_type" to "pdf_text",
                            "page" to pageNum,
                            "transcription" to text,
                            "modified_at" to if (lastModified > 0) lastModified else System.currentTimeMillis(),
                        )
                        // `text` is the trusted bridge entry point; it
                        // explicitly allows the more-specific `pdf_text`
                        // record type and preserves that type in the catalog.
                        indexBridge.indexDirectly(recordMap, "text")
                        records.add(recordMap)
                    }
                }
            }
            if (records.isNotEmpty()) {
                Log.i(LOG_TAG, "Indexed PDF text layer pages=${records.size} uri=$uri")
            }
        } catch (error: Exception) {
            // An invalid/encrypted PDF may still render successfully, so keep
            // the local OCR fallback available rather than abandoning it.
            Log.w(LOG_TAG, "PDF text-layer extraction unavailable uri=$uri", error)
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
            result.text.trim()
        } finally {
            recognizer.close()
        }
    }

    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun isScanSeen(uri: Uri, lastModified: Long): Boolean =
        seenPrefs.getLong(uri.toString(), Long.MIN_VALUE) == lastModified

    private fun markScanSeen(uri: Uri, lastModified: Long) {
        seenPrefs.edit().putLong(uri.toString(), lastModified).apply()
    }

    companion object {
        private const val LOG_TAG = "TeamChaiScanner"
        private const val PDF_OCR_RENDER_SCALE = 2
        const val REQUEST_CODE_PICK_FOLDER = 2001
        const val REQUEST_CODE_PICK_DOCUMENT = 2002
    }
}
