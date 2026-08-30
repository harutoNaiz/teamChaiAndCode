package com.example.team_chai_and_code

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.CalendarContract
import android.provider.DocumentsContract
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Executes only capability-backed, permission-gated OS tools. */
class DeviceToolsBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "execute") {
            result.notImplemented()
            return
        }
        val type = call.argument<String>("type") ?: ""
        val parameters = call.argument<Map<String, Any?>>("parameters") ?: emptyMap()
        try {
            when (type) {
                "create_reminder" -> createReminder(parameters, result)
                "create_note" -> createNote(parameters, result)
                "rename_file" -> renameFile(parameters, result)
                "move_file" -> moveFile(parameters, result)
                "soft_delete_file" -> deleteFile(parameters, result)
                "search_files", "list_files" -> result.success(mapOf("status" to "handled_by_index"))
                else -> result.error("UNSUPPORTED_TOOL", "No native capability for $type", null)
            }
        } catch (error: Throwable) {
            result.error("TOOL_FAILED", error.message ?: error.javaClass.simpleName, null)
        }
    }

    private fun createReminder(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        val title = parameters["title"]?.toString()?.trim().orEmpty()
        require(title.isNotEmpty()) { "Reminder title is required" }
        val intent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, title)
            // `at` may arrive as epoch-millis (planner already resolved a time)
            // or as an ISO-8601 string; either sets the event start so the
            // calendar composer opens pre-filled.
            parseEventBeginMillis(parameters["at"]?.toString())?.let {
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, it)
            }
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(mapOf("status" to "calendar_confirmation_opened"))
    }

    private fun createNote(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        val title = parameters["title"]?.toString()?.trim().orEmpty()
        val content = parameters["content"]?.toString()?.trim().orEmpty()
        // The body is the payload the user asked to capture; a missing title is
        // tolerable (notes apps derive one), an empty body is not.
        require(content.isNotEmpty()) { "Note content is required" }

        // Hand the note to whatever Notes app the user has (Google Keep,
        // Samsung Notes, …) instead of writing a Markdown file ourselves. The
        // note then lives in the user's real notes store — editable, synced —
        // rather than as an orphaned file in the corpus folder.
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            if (title.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, title)
            putExtra(Intent.EXTRA_TEXT, content)
        }
        // Guard before launching: ACTION_SEND/text-plain resolves on virtually
        // every device, but a handler-less device should fail with a clear
        // message rather than an uncaught ActivityNotFoundException.
        if (send.resolveActivity(context.packageManager) == null) {
            error("No app is available to save the note")
        }
        // A chooser lets the user pick the destination app and avoids silently
        // binding to an unexpected default share target.
        val chooser = Intent.createChooser(send, "Save note to…")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
        result.success(mapOf("status" to "note_share_opened"))
    }

    private fun renameFile(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        val uri = Uri.parse(parameters["source_uri"]?.toString() ?: error("source_uri is required"))
        val newName = parameters["new_name"]?.toString()?.trim().orEmpty()
        require(newName.isNotEmpty()) { "new_name is required" }
        val renamed = DocumentsContract.renameDocument(context.contentResolver, uri, newName)
            ?: error("The provider rejected the rename")
        result.success(mapOf("status" to "completed", "uri" to renamed.toString()))
    }

    private fun deleteFile(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        // The Dart layer resolves the planner's filename to an authorised SAF
        // document URI. Deleting it removes the file from the granted tree; the
        // next index scan reconciles it out of AppSearch + the catalog.
        val uri = Uri.parse(parameters["source_uri"]?.toString() ?: error("source_uri is required"))
        val deleted = DocumentsContract.deleteDocument(context.contentResolver, uri)
        if (!deleted) error("The provider rejected the delete")
        result.success(mapOf("status" to "completed", "uri" to uri.toString()))
    }

    private fun moveFile(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        // Contract: the Dart layer resolves the planner's filename to an
        // authorised SAF document URI (source_uri) and passes the target folder
        // NAME (destination). The move stays inside the granted tree — SAF
        // cannot move a document across separate grants/authorities.
        val source = Uri.parse(
            parameters["source_uri"]?.toString() ?: error("source_uri is required"))
        val destinationName = parameters["destination"]?.toString()?.trim().orEmpty()
        require(destinationName.isNotEmpty()) { "A destination folder name is required" }
        val resolver = context.contentResolver

        val writableTree = resolver.persistedUriPermissions
            .firstOrNull { it.isWritePermission && DocumentsContract.isTreeUri(it.uri) }
            ?.uri ?: error("No writable folder is authorised for moves")
        val treeRoot = DocumentsContract.buildDocumentUriUsingTree(
            writableTree, DocumentsContract.getTreeDocumentId(writableTree))

        // Find-or-create the destination subfolder directly under the tree root
        // so repeated "move to Receipts" calls reuse one folder rather than
        // failing or spawning duplicates.
        val destinationDir = findChildDir(resolver, writableTree, treeRoot, destinationName)
            ?: DocumentsContract.createDocument(
                resolver, treeRoot, DocumentsContract.Document.MIME_TYPE_DIR, destinationName)
            ?: error("Could not create destination folder \"$destinationName\"")

        // The corpus keeps every source directly under the tree root, so its
        // parent for the move is that same tree-root document.
        val moved = DocumentsContract.moveDocument(resolver, source, treeRoot, destinationDir)
            ?: error("The provider rejected moving the file into \"$destinationName\"")
        result.success(mapOf(
            "status" to "completed",
            "uri" to moved.toString(),
            "destination" to destinationName))
    }

    /**
     * Returns the tree-root child directory whose display name matches [name]
     * (case-insensitive), or null if none exists yet. Used to reuse an existing
     * destination folder before creating a new one.
     */
    private fun findChildDir(
        resolver: ContentResolver,
        treeUri: Uri,
        parentDoc: Uri,
        name: String,
    ): Uri? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, DocumentsContract.getDocumentId(parentDoc))
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val childMime = cursor.getString(2)
                val childName = cursor.getString(1)
                if (childMime == DocumentsContract.Document.MIME_TYPE_DIR &&
                    childName != null && childName.equals(name, ignoreCase = true)) {
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(0))
                }
            }
        }
        return null
    }

    /**
     * Normalises a reminder `at` value to event-begin millis. Accepts either
     * epoch-millis or an ISO-8601 string; returns null when absent/unparseable
     * so the calendar composer still opens (the user just picks the time).
     */
    private fun parseEventBeginMillis(raw: String?): Long? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null
        // Fast path: already epoch-millis.
        value.toLongOrNull()?.let { return it }
        // ISO parsing needs java.time (API 26+). The app ships without core
        // library desugaring, so never load those classes on older devices —
        // a NoClassDefFoundError there would not be caught below.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        return try {
            // Offset/zoned instant, e.g. "2026-08-30T15:00:00+05:30" or "…Z".
            java.time.OffsetDateTime.parse(value).toInstant().toEpochMilli()
        } catch (_: Exception) {
            try {
                // Zoneless local datetime, e.g. "2026-08-30T15:00" -> device tz.
                java.time.LocalDateTime.parse(value)
                    .atZone(java.time.ZoneId.systemDefault())
                    .toInstant().toEpochMilli()
            } catch (_: Exception) {
                null
            }
        }
    }
}
