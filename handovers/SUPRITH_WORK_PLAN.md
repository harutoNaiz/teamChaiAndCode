# Suprith pickup plan — authorised ingestion, OCR, audio, and acceleration

## Start here

Use the prompt in [`../master/WORKER_PROMPT.md`](../master/WORKER_PROMPT.md).
Read [`../master/ARCHITECTURE.md`](../master/ARCHITECTURE.md), your role section,
and [`LOCAL_INDEX_OCR_HANDOVER.md`](LOCAL_INDEX_OCR_HANDOVER.md). The current
Parakeet UI and OCR references are scaffolds, not working extraction. For S6
also read [`FILE_OPERATION_CONTRACT.md`](FILE_OPERATION_CONTRACT.md).

## Owned paths

Create and own Kotlin code only below:

* `frontend/android/app/src/main/kotlin/com/example/team_chai_and_code/ingestion/`
* `frontend/android/app/src/main/kotlin/com/example/team_chai_and_code/extraction/`
* `frontend/android/app/src/main/kotlin/com/example/team_chai_and_code/workers/`
* Android manifest/permission changes directly required by these packages
* Android integration/device tests

Do not edit Flutter chat widgets, agent coordinator, index ranking, or catalog
internals. Write through the `CatalogWriter` interface supplied by Tushar. Until
it lands, use a local fake implementation in your own test paths.

## Packages — execute in order

- [ ] **S1: source authorisation and discovery.** Implement SAF tree/document
  selection and MediaStore discovery. Persist read permission where Android
  permits it; carry URI, MIME, name, modified time, and availability. Never
  invent `content://` URIs.
- [ ] **S2: unified work pipeline.** Implement a change stream and Android-safe
  scheduled work for authorised sources. Add a user-started burst pass with
  durable progress, pause/resume/cancel, constraints, and URI/version dedupe.
  Both modes must call the same extractor entry point.
- [ ] **S3: document/image extraction.** Prefer native text for documents/PDFs;
  render/scanned pages for local OCR only when needed. Emit non-empty extraction
  records with page and confidence or an explicit typed failure.
- [ ] **S4: local meeting recording/transcription.** Capture a local recording,
  retain an openable recording URI, run a real measured local Parakeet-compatible
  runtime, and emit time-coded `audio_transcript` segments. Delete all simulated
  transcript/sample-text success paths.
- [ ] **S5: Snapdragon evidence.** Benchmark candidates on the Snapdragon Gen 5
  target: script accuracy, retrieval-quality effect, latency, package size, RAM,
  battery, and NPU/GPU/CPU execution. Ship CPU fallback and publish raw numbers.
- [ ] **S6: metadata/capability adapter.** Supply Tushar's query layer with only
  authorised MediaStore/SAF metadata (name, MIME, size, modified/added values,
  relative path/tree membership, content version) and provider-advertised
  move/delete/trash capability. Do not synthesise unavailable creation time or
  use raw paths as authority.

## Contract to produce

```text
CatalogWriter.upsert(source: SourceRecord, extraction: ExtractionRecord)
  -> indexed | typed failure
```

Do not build a second OCR/transcript store. `SourceRecord` points to the original
authorised URI; `ExtractionRecord` points back to source and includes kind,
text, page/segment, confidence, extractor version, and timestamp.

## Required tests and handoff

On a physical Android device prove: authorised poorly named image, PDF page 2,
newly discovered source, burst-indexed old source, changed source replacement,
revoked permission, and recorded audio segment. Run the relevant integration
test with a device ID. Handoff a synthetic fixture producer and benchmark report;
do not commit actual user media/transcripts.

## Done when

The same local pipeline indexes a burst source and a new source; PDF/image/audio
results retain original URI plus extraction provenance; no raw content is sent to
the network; target-device runtime evidence selects an accelerated path or CPU
fallback.
