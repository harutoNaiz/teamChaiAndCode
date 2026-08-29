# File-operation planning and execution contract

This contract is shared by Tushar (planner/executor), Suprith (authorised
metadata/capability adapter), and Vidya (preview/confirmation UI). It covers
future Android file actions; none are implemented yet.

## Authority and scope

Every candidate is an authorised MediaStore or SAF `content://` URI, never a raw
filesystem path. A query is limited to a user-authorised MediaStore collection
or persisted SAF document/tree. SAF provider capabilities and URI permissions
are rechecked immediately before execution.

## Typed request

```text
FileOperationPlan
  operation: LIST | MOVE | RENAME | SOFT_DELETE | RESTORE
  scope: authorised provider collection/tree
  predicate: And | Or | Not | Metadata | Path | Content
  candidate_limit: 1..N (bounded product limit)
  destination: optional authorised tree URI
  requested_by_message_id: stable user turn ID
```

`Metadata` supports MIME/type, size, added/modified/effective-media date, and
only provider-supplied fields. `Path` supports display-name contains/glob and
provider-relative path/tree membership. `Content` queries the existing local
extraction index and returns source IDs—not extraction text as an execution
target.

## Candidate and preview

```text
CandidateFile
  source_id, authorised_uri, display_name, mime_type, metadata
  matching_predicates, provider_capabilities, content_version

PreviewManifest
  immutable candidate list + count, operation, destination, risks,
  undo/trash availability, generated timestamp, manifest hash
```

The resolver deduplicates source IDs that match multiple extraction/page records
and evaluates compound predicates deterministically. `LIST` returns candidates
only. Any mutation is blocked until the user explicitly confirms the manifest.

## Execution and safety

1. Re-read each candidate's URI permission, provider capability, and version.
2. Exclude and report changed, missing, revoked, or unsupported candidates.
3. If actual count differs from preview, require a new preview/confirmation.
4. Use provider-supported move/rename/trash/recoverable delete only.
5. Record a local audit receipt: plan, manifest hash, confirmation, per-URI
   outcome, timestamps, and undo/trash reference.
6. Permanent deletion is not supported in the first release.

## Example

```text
"Delete all PDFs containing John created before 2020"
  -> SOFT_DELETE
  -> AND(mime == application/pdf,
         content contains "John",
         effective_date < 2020-01-01)
  -> candidate preview -> explicit confirmation -> provider trash if supported
```

## Tests required before enabling mutations

* metadata-only, name/path-only, content-only, and compound predicate resolution;
* ambiguous/unavailable creation dates do not silently become a creation filter;
* duplicate extraction/page hits result in one source candidate;
* revoked URI, changed version, unsupported provider, and oversized candidate
  set fail safely;
* preview/confirmation mismatch blocks execution;
* supported soft-delete produces an audit/undo receipt; permanent delete is
  rejected.
