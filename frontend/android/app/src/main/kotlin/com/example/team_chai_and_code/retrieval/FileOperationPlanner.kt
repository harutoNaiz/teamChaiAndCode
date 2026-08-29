package com.example.team_chai_and_code.retrieval

import java.security.MessageDigest

enum class FileOperation { LIST, MOVE, RENAME, SOFT_DELETE, RESTORE }

sealed interface FilePredicate {
    data class And(val children: List<FilePredicate>) : FilePredicate
    data class Or(val children: List<FilePredicate>) : FilePredicate
    data class Not(val child: FilePredicate) : FilePredicate
    data class MimeType(val values: Set<String>) : FilePredicate
    data class NameContains(val value: String) : FilePredicate
    data class RelativePathContains(val value: String) : FilePredicate
    data class SizeAtLeast(val bytes: Long) : FilePredicate
    data class ModifiedBefore(val millis: Long) : FilePredicate
    data class AddedBefore(val millis: Long) : FilePredicate
    data class ContentSourceIds(val sourceIds: Set<String>) : FilePredicate
}

data class FileOperationPlan(
    val operation: FileOperation,
    val scopeId: String,
    val predicate: FilePredicate,
    val candidateLimit: Int = 100,
    val destinationUri: String? = null,
    val requestedByMessageId: String,
) {
    init {
        require(scopeId.isNotBlank()) { "scopeId is required" }
        require(requestedByMessageId.isNotBlank()) { "requestedByMessageId is required" }
        require(candidateLimit in 1..500) { "candidateLimit must be between 1 and 500" }
        require((operation == FileOperation.MOVE) == (destinationUri != null)) {
            "MOVE requires a destination URI and other operations must not supply one"
        }
    }
}

data class FileMetadata(
    val sourceId: String,
    val uri: String,
    val displayName: String,
    val mimeType: String,
    val relativePath: String? = null,
    val sizeBytes: Long? = null,
    val addedAtMillis: Long? = null,
    val modifiedAtMillis: Long? = null,
    val contentVersion: String,
    val supportsMove: Boolean = false,
    val supportsRename: Boolean = false,
    val supportsTrash: Boolean = false,
    val supportsRestore: Boolean = false,
)

data class CandidateFile(val metadata: FileMetadata, val matchingReasons: Set<String>)

data class PreviewManifest(
    val plan: FileOperationPlan,
    val candidates: List<CandidateFile>,
    val manifestHash: String,
    val generatedAtMillis: Long,
    val undoAvailable: Boolean,
)

/** Pure deterministic planner. Providers supply only already-authorised metadata. */
class FileOperationPlanner {
    fun resolve(plan: FileOperationPlan, files: Collection<FileMetadata>): List<CandidateFile> {
        return files.asSequence()
            .filter { matches(plan.predicate, it) }
            .map { CandidateFile(it, matchingReasons(plan.predicate, it)) }
            .distinctBy { it.metadata.sourceId }
            .take(plan.candidateLimit)
            .toList()
    }

    fun preview(plan: FileOperationPlan, candidates: List<CandidateFile>, nowMillis: Long): PreviewManifest {
        require(candidates.isNotEmpty() || plan.operation == FileOperation.LIST) {
            "Mutating operations require at least one candidate"
        }
        candidates.forEach { candidate -> require(capable(plan.operation, candidate.metadata)) {
            "Provider does not support ${plan.operation} for ${candidate.metadata.displayName}"
        } }
        val canonical = candidates.joinToString("|") { "${it.metadata.sourceId}:${it.metadata.contentVersion}" }
        val hash = MessageDigest.getInstance("SHA-256").digest(
            "${plan.operation}:${plan.scopeId}:${plan.destinationUri}:$canonical".toByteArray()
        ).joinToString("") { "%02x".format(it) }
        return PreviewManifest(plan, candidates, hash, nowMillis,
            candidates.all { it.metadata.supportsTrash || it.metadata.supportsRestore })
    }

    private fun capable(operation: FileOperation, file: FileMetadata): Boolean = when (operation) {
        FileOperation.LIST -> true
        FileOperation.MOVE -> file.supportsMove
        FileOperation.RENAME -> file.supportsRename
        FileOperation.SOFT_DELETE -> file.supportsTrash
        FileOperation.RESTORE -> file.supportsRestore
    }

    private fun matches(predicate: FilePredicate, file: FileMetadata): Boolean = when (predicate) {
        is FilePredicate.And -> predicate.children.all { matches(it, file) }
        is FilePredicate.Or -> predicate.children.any { matches(it, file) }
        is FilePredicate.Not -> !matches(predicate.child, file)
        is FilePredicate.MimeType -> file.mimeType in predicate.values
        is FilePredicate.NameContains -> file.displayName.contains(predicate.value, ignoreCase = true)
        is FilePredicate.RelativePathContains -> file.relativePath?.contains(predicate.value, ignoreCase = true) == true
        is FilePredicate.SizeAtLeast -> file.sizeBytes?.let { it >= predicate.bytes } == true
        is FilePredicate.ModifiedBefore -> file.modifiedAtMillis?.let { it < predicate.millis } == true
        is FilePredicate.AddedBefore -> file.addedAtMillis?.let { it < predicate.millis } == true
        is FilePredicate.ContentSourceIds -> file.sourceId in predicate.sourceIds
    }

    private fun matchingReasons(predicate: FilePredicate, file: FileMetadata): Set<String> = when (predicate) {
        is FilePredicate.And -> predicate.children.flatMap { matchingReasons(it, file) }.toSet()
        is FilePredicate.Or -> predicate.children.filter { matches(it, file) }
            .flatMap { matchingReasons(it, file) }.toSet()
        is FilePredicate.Not -> setOf("not")
        is FilePredicate.MimeType -> setOf("mime_type")
        is FilePredicate.NameContains -> setOf("display_name")
        is FilePredicate.RelativePathContains -> setOf("relative_path")
        is FilePredicate.SizeAtLeast -> setOf("size")
        is FilePredicate.ModifiedBefore -> setOf("modified_at")
        is FilePredicate.AddedBefore -> setOf("added_at")
        is FilePredicate.ContentSourceIds -> setOf("extracted_content")
    }
}
