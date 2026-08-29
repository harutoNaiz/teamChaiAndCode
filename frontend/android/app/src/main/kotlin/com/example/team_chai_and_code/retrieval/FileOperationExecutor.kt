package com.example.team_chai_and_code.retrieval

interface FileCapabilityProvider {
    /** Re-resolves a URI and returns null when it is missing or permission was revoked. */
    fun current(uri: String): FileMetadata?
    fun move(uri: String, destinationUri: String): ActionOutcome
    fun rename(uri: String, newName: String): ActionOutcome
    fun softDelete(uri: String): ActionOutcome
    fun restore(uri: String): ActionOutcome
}

sealed interface ActionOutcome {
    object Completed : ActionOutcome
    data class Failed(val reason: String) : ActionOutcome
}

data class FileActionReceipt(
    val manifestHash: String,
    val executedAtMillis: Long,
    val outcomes: Map<String, ActionOutcome>,
)

/** Executes only an already-previewed manifest after caller obtained confirmation. */
class FileOperationExecutor(private val provider: FileCapabilityProvider) {
    fun execute(manifest: PreviewManifest, confirmedManifestHash: String, nowMillis: Long,
                renameTo: String? = null): FileActionReceipt {
        require(manifest.manifestHash == confirmedManifestHash) { "Confirmation does not match preview" }
        if (manifest.plan.operation == FileOperation.LIST) {
            return FileActionReceipt(manifest.manifestHash, nowMillis, emptyMap())
        }
        val outcomes = linkedMapOf<String, ActionOutcome>()
        manifest.candidates.forEach { candidate ->
            val current = provider.current(candidate.metadata.uri)
            if (current == null || current.uri != candidate.metadata.uri ||
                current.contentVersion != candidate.metadata.contentVersion) {
                outcomes[candidate.metadata.sourceId] = ActionOutcome.Failed("Source changed, missing, or unavailable")
                return@forEach
            }
            if (!capable(manifest.plan.operation, current)) {
                outcomes[current.sourceId] = ActionOutcome.Failed("Provider capability changed since preview")
                return@forEach
            }
            val outcome = when (manifest.plan.operation) {
                FileOperation.MOVE -> provider.move(current.uri, manifest.plan.destinationUri!!)
                FileOperation.RENAME -> if (renameTo.isNullOrBlank()) ActionOutcome.Failed("New name is required") else provider.rename(current.uri, renameTo)
                FileOperation.SOFT_DELETE -> provider.softDelete(current.uri)
                FileOperation.RESTORE -> provider.restore(current.uri)
                FileOperation.LIST -> ActionOutcome.Completed
            }
            outcomes[current.sourceId] = outcome
        }
        return FileActionReceipt(manifest.manifestHash, nowMillis, outcomes)
    }

    private fun capable(operation: FileOperation, file: FileMetadata): Boolean = when (operation) {
        FileOperation.LIST -> true
        FileOperation.MOVE -> file.supportsMove
        FileOperation.RENAME -> file.supportsRename
        FileOperation.SOFT_DELETE -> file.supportsTrash
        FileOperation.RESTORE -> file.supportsRestore
    }
}
