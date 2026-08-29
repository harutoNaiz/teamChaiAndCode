# Local index scanner and OCR handover

## Purpose

This handover gives Suprith the contract for connecting his phone scanner and OCR-capable model to the local index already in this repository.

The index is already responsible for storing searchable text and returning the original source reference. Suprith's pipeline is responsible for discovering only user-authorised content, obtaining a valid Android URI, reading the image or document, running OCR, and sending the resulting JSON record to the index.

The scanner must never upload source content or OCR text to a network service unless a future product decision explicitly permits it.

## Ownership boundary

```json
{
  "scanner_and_ocr_owner": [
    "Ask for access through Android's document picker or another Android-approved source.",
    "Persist Android permission for every selected source when Android allows it.",
    "Find changed files only inside user-authorised locations.",
    "Read the source, run the selected local OCR/model, and report failures.",
    "Create the JSON index record below."
  ],
  "existing_index_owner": [
    "Store text locally in AppSearch.",
    "Replace stale records for the same source URI and page.",
    "Search text immediately and return a snippet, transcription, and source URI.",
    "Keep no second OCR-only index."
  ],
  "not_part_of_this_handover": [
    "Flutter search UI and result rendering.",
    "Cloud sync or uploading private content.",
    "Changing the index schema without agreement in master.",
    "Operating-system actions such as deleting files."
  ]
}
```

## Required flow

```json
{
  "flow": [
    {
      "step": 1,
      "component": "scanner",
      "input": "User-selected directory or document",
      "output": "A persisted Android content:// URI with read permission"
    },
    {
      "step": 2,
      "component": "scanner",
      "input": "content:// URI",
      "output": "mime type, display name, modification time, page/image unit"
    },
    {
      "step": 3,
      "component": "local OCR/model",
      "input": "image or rendered PDF page",
      "output": "OCR transcription and optional confidence"
    },
    {
      "step": 4,
      "component": "index bridge",
      "input": "index_ocr JSON record",
      "output": "local AppSearch write result"
    },
    {
      "step": 5,
      "component": "search",
      "input": "user query",
      "output": "matching transcription, snippet, and the same source URI"
    }
  ]
}
```

A URI is valid only when the app can read it because the user granted access. Do not invent a `content://` URI from a filesystem path. The Android test showed that an invented URI is rejected by Android.

## Scanner output contract

The scanner produces this JSON before calling the index. One image produces one record. A PDF may produce one record per page.

```json
{
  "operation": "index_ocr",
  "record": {
    "id": "sha256-of-source-uri-and-content-version",
    "source_uri": "content://provider/document/opaque-id",
    "display_name": "unhelpfully-named-photo.jpg",
    "mime_type": "image/jpeg",
    "content_type": "image_ocr",
    "transcription": "Government of India Aadhaar Example Person ...",
    "page": null,
    "ocr_confidence": 0.96,
    "modified_at": 1789590600000
  }
}
```

Field rules:

```json
{
  "id": "Required non-empty string. Change when source content changes.",
  "source_uri": "Required persisted Android content:// URI. It must open the exact original source.",
  "display_name": "Required non-empty user-visible filename.",
  "mime_type": "Required non-empty MIME type.",
  "content_type": {
    "allowed_with_indexText": ["text", "pdf_text"],
    "allowed_with_indexOcr": ["image_ocr", "pdf_ocr"]
  },
  "transcription": "Required non-empty extracted or OCR text.",
  "page": "Optional positive integer. Use for a PDF page or scanned-page unit.",
  "ocr_confidence": "Optional number from 0.0 through 1.0.",
  "modified_at": "Optional positive integer Unix time in milliseconds."
}
```

Call the existing Flutter-facing bridge with the `record` object itself:

```json
{
  "method": "indexOcr",
  "arguments": {
    "id": "sha256-of-source-uri-and-content-version",
    "source_uri": "content://provider/document/opaque-id",
    "display_name": "unhelpfully-named-photo.jpg",
    "mime_type": "image/jpeg",
    "content_type": "image_ocr",
    "transcription": "OCR text",
    "ocr_confidence": 0.96,
    "modified_at": 1789590600000
  }
}
```

For plain document text or native PDF text, call `indexText` and set `content_type` to `text` or `pdf_text`.

## Index response and search contract

A successful write returns:

```json
{
  "id": "sha256-of-source-uri-and-content-version",
  "indexed": true,
  "open_uri": "content://provider/document/opaque-id"
}
```

A search call and result are:

```json
{
  "request": {
    "method": "search",
    "arguments": {
      "q": "aadhaar number"
    }
  },
  "result": {
    "identifier": "sha256-of-source-uri-and-content-version",
    "source_uri": "content://provider/document/opaque-id",
    "open_uri": "content://provider/document/opaque-id",
    "display_name": "unhelpfully-named-photo.jpg",
    "mime_type": "image/jpeg",
    "content_type": "image_ocr",
    "transcription": "Government of India Aadhaar Example Person ...",
    "page": null,
    "ocr_confidence": 0.96,
    "modified_at": 1789590600000,
    "snippet": "Government of India Aadhaar Example Person ..."
  }
}
```

The scanner must retain the source URI in every record. The model must never return only OCR text without that source connection.

## Change and failure contract

```json
{
  "change_handling": {
    "same_source_uri_and_page": "A newer record replaces the older record. Old transcription must stop appearing in search.",
    "unchanged_source": "Do not re-run OCR when the stored content version and modified_at value still match.",
    "missing_or_revoked_source": "Do not search stale content as current. Report the source as unavailable and schedule removal through the index owner."
  },
  "failure_handling": {
    "permission_denied": "Do not index. Return a permission-required state to the caller.",
    "unreadable_file": "Do not index empty text. Return a source-read failure.",
    "ocr_failed": "Do not index empty text. Return an OCR failure with source URI and reason.",
    "unsupported_mime_type": "Do not pretend OCR succeeded. Return unsupported-source."
  }
}
```

## Acceptance contract

Suprith's change is complete only when all three goals below are demonstrated on an Android device.

```json
{
  "goals": [
    {
      "id": "authorised-photo-ocr-is-searchable",
      "given": "A user authorises a folder or image containing a poorly named test photo with a unique visible phrase.",
      "when": "The scanner reads the valid content URI and the local OCR model produces a non-empty transcription.",
      "then": "The pipeline calls indexOcr and a search for the unique phrase returns the transcription and the same open_uri.",
      "proof": "Device test output shows the query, returned phrase, and an Android-openable source URI."
    },
    {
      "id": "pdf-or-document-page-keeps-provenance",
      "given": "A user-authorised multi-page document with a unique phrase on page 2.",
      "when": "The pipeline extracts native text or OCRs page 2 and calls indexText or indexOcr.",
      "then": "Search returns content_type pdf_text or pdf_ocr, page 2, the correct source URI, and the matching text.",
      "proof": "Device test asserts content_type, page, transcription, and open_uri."
    },
    {
      "id": "changed-source-replaces-old-text",
      "given": "One authorised source is indexed with an old unique phrase and later changes to a new unique phrase.",
      "when": "The scanner detects the content-version or modified_at change and re-indexes it.",
      "then": "The old phrase has no result and the new phrase returns exactly the current source record.",
      "proof": "Device test searches both phrases after re-indexing and records the expected empty/current results."
    }
  ]
}
```

## Existing verification

The repository already contains a device integration test for direct index writes, OCR-style records, stale replacement, PDF page metadata, source references, and the 20-result cap. Suprith should extend that test with real picker-granted sources rather than replacing it.

```json
{
  "existing_test": "frontend/integration_test/local_index_device_test.dart",
  "run_from": "frontend",
  "command": "flutter test integration_test/local_index_device_test.dart -d <android-device-id>",
  "required_new_test_focus": "Real source permission, actual file read, model OCR output, and URI opening."
}
```
