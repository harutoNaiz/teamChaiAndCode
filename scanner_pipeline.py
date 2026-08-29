"""Local document scanner, background cron watcher, multimodal extraction, and vector memory pipeline.

Implements the contract defined in LOCAL_INDEX_OCR_HANDOVER.md and ROLES.md for Suprith's ownership.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import os
import threading
import time
from typing import Any, Callable, Protocol

from local_index import IndexStore, IndexedRecord


SUPPORTED_IMAGE_MIMES = {"image/jpeg", "image/png", "image/webp", "image/heic"}
SUPPORTED_DOC_MIMES = {"application/pdf", "text/plain", "text/markdown"}


@dataclass(frozen=True)
class ModelCapability:
    model_id: str
    is_local: bool
    context_limit: int
    supported_tasks: list[str]
    is_available: bool
    acceleration: str = "cpu"
    failure_reason: str | None = None


class OcrEngine(Protocol):
    """Local OCR / vision-model engine interface with CPU fallback."""
    def extract_image_text(self, source_path_or_bytes: str | bytes) -> tuple[str, float]: ...


class DefaultLocalOcrEngine:
    """Adapter for an explicitly supplied local OCR runtime.

    The Python pipeline is a development harness, not an Android OCR runtime.  It
    must never turn arbitrary image/PDF bytes into purported OCR text.
    """

    def __init__(self, backend_runner: Callable[[str | bytes], tuple[str, float]] | None = None) -> None:
        self._backend = backend_runner
        self._capability = ModelCapability(
            model_id="local-ocr-mlkit-v1",
            is_local=True,
            context_limit=4096,
            supported_tasks=["ocr", "transcription", "page_ocr"],
            is_available=backend_runner is not None,
            acceleration="test_or_host_backend" if backend_runner else "unavailable",
            failure_reason=None if backend_runner else "No host OCR backend has been configured",
        )

    @property
    def capability(self) -> ModelCapability:
        return self._capability

    def extract_image_text(self, source_path_or_bytes: str | bytes) -> tuple[str, float]:
        if self._backend:
            return self._backend(source_path_or_bytes)
        return "", 0.0


class OpenRouterMultimodalExtractor:
    """Compatibility wrapper that keeps private source bytes on-device.

    Remote multimodal extraction is intentionally disabled: source files and OCR
    text must not be uploaded by an indexing pipeline.
    """

    def __init__(
        self,
        api_key: str | None = None,
        model_id: str = "google/gemini-2.5-flash",
        fallback_engine: OcrEngine | None = None,
    ) -> None:
        self.api_key = None
        self.model_id = model_id
        self.fallback = fallback_engine or DefaultLocalOcrEngine()

    def reason_and_extract(
        self,
        content_bytes: bytes,
        mime_type: str,
        prompt: str = "Extract all text, structured details, and key entities from this document concisely.",
    ) -> tuple[str, float]:
        """Always use the local fallback until an explicit privacy decision exists."""
        return self.fallback.extract_image_text(content_bytes)


@dataclass
class ScanResult:
    status: str
    record_id: str | None = None
    source_uri: str | None = None
    open_uri: str | None = None
    reason: str | None = None
    error: str | None = None
    records: list[IndexedRecord] = field(default_factory=list)


class LocalScannerPipeline:
    """Permission-aware phone scanner, multimodal extractor, and vector memory ingestion pipeline."""

    def __init__(
        self,
        index_store: IndexStore,
        ocr_engine: OcrEngine | None = None,
        multimodal_extractor: OpenRouterMultimodalExtractor | None = None,
    ) -> None:
        self.index_store = index_store
        self.ocr_engine = ocr_engine or DefaultLocalOcrEngine()
        self.multimodal = multimodal_extractor or OpenRouterMultimodalExtractor(fallback_engine=self.ocr_engine)
        self._processed_versions: dict[str, str] = {}

    @staticmethod
    def compute_content_id(source_uri: str, content: bytes, page: int | None = None) -> str:
        h = hashlib.sha256()
        h.update(source_uri.encode("utf-8"))
        if page is not None:
            h.update(f":page:{page}".encode("utf-8"))
        h.update(content)
        return h.hexdigest()

    def process_source(
        self,
        source_uri: str,
        display_name: str,
        mime_type: str,
        content: bytes | None = None,
        file_path: str | None = None,
        has_permission: bool = True,
        modified_at: int | None = None,
        page: int | None = None,
        use_multimodal: bool = False,
    ) -> ScanResult:
        """Processes a single source item, extracts text/reasoning, and indexes into vector memory."""
        if not has_permission:
            return ScanResult(
                status="permission_denied",
                source_uri=source_uri,
                error="Permission denied: user has not granted access to source",
            )

        if mime_type not in SUPPORTED_IMAGE_MIMES and mime_type not in SUPPORTED_DOC_MIMES:
            return ScanResult(
                status="unsupported_mime_type",
                source_uri=source_uri,
                reason=f"Unsupported MIME type: {mime_type}",
            )

        raw_bytes = content
        if raw_bytes is None and file_path:
            try:
                with open(file_path, "rb") as f:
                    raw_bytes = f.read()
            except Exception as e:
                return ScanResult(
                    status="unreadable_file",
                    source_uri=source_uri,
                    error=f"Cannot read file: {e}",
                )

        if raw_bytes is None or len(raw_bytes) == 0:
            return ScanResult(
                status="unreadable_file",
                source_uri=source_uri,
                error="Empty content or unreadable file source",
            )

        current_hash = hashlib.sha256(raw_bytes).hexdigest()
        source_version_key = f"{source_uri}|{page or 0}"
        if self._processed_versions.get(source_version_key) == current_hash:
            return ScanResult(
                status="unchanged",
                source_uri=source_uri,
                reason="Content is unchanged since last indexing; skipping OCR",
            )

        content_type: str
        transcription: str
        confidence: float | None = None

        if mime_type in SUPPORTED_IMAGE_MIMES:
            content_type = "image_ocr"
            try:
                if use_multimodal:
                    transcription, confidence = self.multimodal.reason_and_extract(raw_bytes, mime_type)
                else:
                    transcription, confidence = self.ocr_engine.extract_image_text(raw_bytes)
            except Exception as e:
                return ScanResult(
                    status="ocr_failed",
                    source_uri=source_uri,
                    error=f"OCR execution failed: {e}",
                )
            if not transcription.strip():
                return ScanResult(
                    status="ocr_failed",
                    source_uri=source_uri,
                    error="OCR returned empty transcription",
                )
        elif mime_type == "application/pdf":
            content_type = "pdf_text" if page is None else "pdf_ocr"
            try:
                if use_multimodal:
                    transcription, confidence = self.multimodal.reason_and_extract(raw_bytes, mime_type)
                else:
                    transcription, confidence = self.ocr_engine.extract_image_text(raw_bytes)
            except Exception as e:
                return ScanResult(
                    status="ocr_failed",
                    source_uri=source_uri,
                    error=f"PDF extraction failed: {e}",
                )
            if not transcription.strip():
                return ScanResult(
                    status="unreadable_file",
                    source_uri=source_uri,
                    error="PDF page contains no readable text",
                )
        else:
            content_type = "text"
            transcription = raw_bytes.decode("utf-8", errors="ignore").strip()
            if not transcription:
                return ScanResult(
                    status="unreadable_file",
                    source_uri=source_uri,
                    error="Text source is empty",
                )

        record_id = self.compute_content_id(source_uri, raw_bytes, page=page)
        record = IndexedRecord(
            identifier=record_id,
            source_uri=source_uri,
            display_name=display_name,
            mime_type=mime_type,
            content_type=content_type,
            transcription=transcription,
            page=page,
            ocr_confidence=confidence,
            modified_at=modified_at or int(time.time() * 1000),
        )

        self.index_store.upsert(record)
        self._processed_versions[source_version_key] = current_hash

        return ScanResult(
            status="indexed",
            record_id=record_id,
            source_uri=source_uri,
            open_uri=source_uri,
            records=[record],
        )


class BackgroundFileSystemCronWatcher:
    """Development-only filesystem watcher used by host tests.

    It is intentionally not an Android background worker and must not be used
    as a substitute for SAF/MediaStore permission-aware indexing on device.
    """

    def __init__(
        self,
        pipeline: LocalScannerPipeline,
        watch_paths: list[str] | None = None,
        poll_interval_seconds: float = 5.0,
    ) -> None:
        self.pipeline = pipeline
        self.watch_paths = watch_paths or []
        self.poll_interval = poll_interval_seconds
        self._running = False
        self._thread: threading.Thread | None = None
        self._scanned_count = 0

    def add_watch_path(self, path: str) -> None:
        if path not in self.watch_paths and os.path.exists(path):
            self.watch_paths.append(path)

    def scan_once(self) -> int:
        """Executes a single cron pass over watched directories."""
        newly_indexed = 0
        for root_path in self.watch_paths:
            if not os.path.exists(root_path):
                continue
            for root, _, files in os.walk(root_path):
                for filename in files:
                    file_path = os.path.join(root, filename)
                    ext = os.path.splitext(filename)[1].lower()
                    
                    mime_type = "application/octet-stream"
                    if ext in {".jpg", ".jpeg"}:
                        mime_type = "image/jpeg"
                    elif ext == ".png":
                        mime_type = "image/png"
                    elif ext == ".pdf":
                        mime_type = "application/pdf"
                    elif ext in {".txt", ".md", ".log"}:
                        mime_type = "text/plain"
                    else:
                        continue

                    # Development-only local URI. Production Android scanning
                    # must receive a user-authorised SAF/MediaStore content URI.
                    source_uri = f"file://{file_path}"
                    mod_time = int(os.path.getmtime(file_path) * 1000)
                    
                    result = self.pipeline.process_source(
                        source_uri=source_uri,
                        display_name=filename,
                        mime_type=mime_type,
                        file_path=file_path,
                        modified_at=mod_time,
                    )
                    if result.status == "indexed":
                        newly_indexed += 1
                        self._scanned_count += 1
        return newly_indexed

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread:
            self._thread.join(timeout=1.0)
            self._thread = None

    def _loop(self) -> None:
        while self._running:
            try:
                self.scan_once()
            except Exception:
                pass
            time.sleep(self.poll_interval)
