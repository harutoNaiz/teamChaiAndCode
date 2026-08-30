package com.example.team_chai_and_code

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.CalendarContract
import android.provider.DocumentsContract
import android.provider.MediaStore
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
            parameters["at"]?.toString()?.toLongOrNull()?.let {
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, it)
            }
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(mapOf("status" to "calendar_confirmation_opened"))
    }

    private fun createNote(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        val title = parameters["title"]?.toString()?.trim().orEmpty()
        val content = parameters["content"]?.toString()?.trim().orEmpty()
        require(title.isNotEmpty()) { "Note title is required" }
        require(content.isNotEmpty()) { "Note content is required" }
        val filename = if (title.endsWith(".md")) title else "$title.md"
        val resolver = context.contentResolver

        // 1) Preferred: create the note inside a folder the user already granted
        //    AND that the scanner walks, so the file is written with its content
        //    (ACTION_CREATE_DOCUMENT alone only makes an empty file — it never
        //    persists EXTRA_TEXT) and is immediately indexable, with no second
        //    picker. Needs a write-persisted tree grant.
        val writableTree = resolver.persistedUriPermissions
            .firstOrNull { it.isWritePermission && DocumentsContract.isTreeUri(it.uri) }
            ?.uri
        if (writableTree != null) {
            val parentDoc = DocumentsContract.buildDocumentUriUsingTree(
                writableTree, DocumentsContract.getTreeDocumentId(writableTree))
            val docUri = DocumentsContract.createDocument(
                resolver, parentDoc, "text/markdown", filename)
                ?: error("The folder provider rejected note creation")
            resolver.openOutputStream(docUri)?.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                ?: error("Could not open the new note for writing")
            result.success(mapOf("status" to "completed", "uri" to docUri.toString(),
                "display_name" to filename))
            return
        }

        // 2) No writable tree yet, but a read tree exists (scanner is set up).
        //    Write the note into that same physical folder via MediaStore so it
        //    still lands where the scanner looks, without needing a picker. The
        //    read tree's document id encodes the relative path, e.g.
        //    "primary:Download/teamchai-test".
        val readTree = resolver.persistedUriPermissions
            .firstOrNull { it.isReadPermission && DocumentsContract.isTreeUri(it.uri) }
            ?.uri
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && readTree != null) {
            val relPath = DocumentsContract.getTreeDocumentId(readTree)
                .substringAfter(':').trim('/')
            if (relPath.startsWith("Download", ignoreCase = true)) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, filename)
                    put(MediaStore.Downloads.MIME_TYPE, "text/markdown")
                    put(MediaStore.Downloads.RELATIVE_PATH, relPath)
                }
                val docUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: error("Could not create the note in $relPath")
                resolver.openOutputStream(docUri)?.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                    ?: error("Could not open the new note for writing")
                result.success(mapOf("status" to "completed", "uri" to docUri.toString(),
                    "display_name" to filename))
                return
            }
        }

        // 3) Nothing granted yet: fall back to the system create-document picker.
        //    A fire-and-forget intent cannot write content, so this only creates
        //    the file; the user is nudged to grant a folder for the seamless path.
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/markdown"
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(mapOf("status" to "note_save_confirmation_opened"))
    }

    private fun renameFile(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        val uri = Uri.parse(parameters["source_uri"]?.toString() ?: error("source_uri is required"))
        val newName = parameters["new_name"]?.toString()?.trim().orEmpty()
        require(newName.isNotEmpty()) { "new_name is required" }
        val renamed = DocumentsContract.renameDocument(context.contentResolver, uri, newName)
            ?: error("The provider rejected the rename")
        result.success(mapOf("status" to "completed", "uri" to renamed.toString()))
    }

    private fun moveFile(parameters: Map<String, Any?>, result: MethodChannel.Result) {
        val source = Uri.parse(parameters["source_uri"]?.toString() ?: error("source_uri is required"))
        val sourceParent = Uri.parse(parameters["source_parent_uri"]?.toString() ?: error("source_parent_uri is required"))
        val destination = Uri.parse(parameters["destination_uri"]?.toString() ?: error("destination_uri is required"))
        val moved = DocumentsContract.moveDocument(context.contentResolver, source, sourceParent, destination)
            ?: error("The provider rejected the move")
        result.success(mapOf("status" to "completed", "uri" to moved.toString()))
    }
}
