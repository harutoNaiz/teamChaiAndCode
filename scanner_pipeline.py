"""Local document scanner, background cron watcher, multimodal extraction, and vector memory pipeline.

Implements the contract defined in LOCAL_INDEX_OCR_HANDOVER.md and ROLES.md for Suprith's ownership.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import csv
import hashlib
import os
import tempfile
import threading
import time
from threading import RLock
from typing import Any, Callable, Protocol

from local_index import IndexStore, IndexedRecord


SUPPORTED_IMAGE_MIMES = {"image/jpeg", "image/png", "image/webp", "image/heic"}
SUPPORTED_DOC_MIMES = {"application/pdf", "text/plain", "text/markdown"}

# Development-only extension to MIME mapping shared by the host filesystem
# scanners. Production Android discovery uses the provider-reported MIME type,
# never a filename extension.
_EXTENSION_MIME_MAP = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".pdf": "application/pdf",
    ".txt": "text/plain",
    ".log": "text/plain",
    ".md": "text/markdown",
    ".markdown": "text/markdown",
}


def mime_for_extension(filename: str) -> str | None:
    """Best-effort MIME guess for a host file, or None when it is unsupported."""
    ext = os.path.splitext(filename)[1].lower()
    return _EXTENSION_MIME_MAP.get(ext)


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
                    mime_type = mime_for_extension(filename)
                    if mime_type is None:
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


CATALOG_FIELDS = [
    "index_id",
    "source_uri",
    "display_name",
    "mime_type",
    "content_type",
    "page",
    "content_version",
    "modified_at",
    "ocr_confidence",
    "indexed_at",
    "transcription",
]


def _normalize_page(page: Any) -> str:
    if page is None or page == "":
        return ""
    return str(page)


def _catalog_unit_key(source_uri: str, page: Any) -> str:
    return f"{source_uri}|{_normalize_page(page)}"


class CsvCatalogStore:
    """Durable CSV catalog: the persistent "seen files" record for refresh scans.

    Per master/ARCHITECTURE.md the CSV is an audit/join export, never the search
    engine. Its job here is to let a system-wide refresh skip files already
    indexed at their current content version instead of re-reading and
    re-extracting them. LocalTextIndex stays authoritative for retrieval.

    One logical source unit is (source_uri, page). A new content version
    replaces the prior row for that unit, mirroring the index's stale-replacement
    rule so old text stops being exported.
    """

    def __init__(self, csv_path: str) -> None:
        self.csv_path = csv_path
        self._lock = RLock()
        self._rows: dict[str, dict[str, str]] = {}
        self._versions: dict[str, str] = {}
        self._load()

    def _load(self) -> None:
        if not os.path.exists(self.csv_path):
            return
        with open(self.csv_path, newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                key = _catalog_unit_key(row.get("source_uri", ""), row.get("page", ""))
                self._rows[key] = {field: row.get(field, "") for field in CATALOG_FIELDS}
                self._versions[key] = row.get("content_version", "")

    def is_indexed(self, source_uri: str, page: Any, content_version: str) -> bool:
        """True when this unit is already recorded at exactly this content version."""
        with self._lock:
            return self._versions.get(_catalog_unit_key(source_uri, page)) == content_version

    def upsert_row(self, row: dict[str, Any], *, flush: bool = True) -> None:
        """Record (or replace) the row for one source unit."""
        if not row.get("source_uri"):
            raise ValueError("source_uri is required")
        key = _catalog_unit_key(row["source_uri"], row.get("page"))
        normalized = {field: "" for field in CATALOG_FIELDS}
        for field in CATALOG_FIELDS:
            value = row.get(field)
            normalized[field] = "" if value is None else str(value)
        normalized["page"] = _normalize_page(row.get("page"))
        with self._lock:
            self._rows[key] = normalized
            self._versions[key] = normalized["content_version"]
            if flush:
                self._flush()

    def flush(self) -> None:
        with self._lock:
            self._flush()

    def _flush(self) -> None:
        directory = os.path.dirname(self.csv_path) or "."
        os.makedirs(directory, exist_ok=True)
        fd, temp_path = tempfile.mkstemp(dir=directory, suffix=".tmp")
        try:
            with os.fdopen(fd, "w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=CATALOG_FIELDS)
                writer.writeheader()
                for key in sorted(self._rows):
                    writer.writerow(self._rows[key])
            os.replace(temp_path, self.csv_path)
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    @property
    def row_count(self) -> int:
        with self._lock:
            return len(self._rows)


class RefreshScanner:
    """User-triggered system-wide refresh over host directories.

    Development harness for the "Refresh" button. It walks each authorised root,
    skips any file already recorded in the CSV catalog at its current
    (size, mtime) version, and runs the shared extraction pipeline only for new
    or changed files. Production Android uses SAF/MediaStore discovery over
    user-authorised trees, not a raw filesystem walk, but the skip-if-seen and
    CSV-catalog contract is identical.
    """

    def __init__(self, pipeline: "LocalScannerPipeline", catalog: CsvCatalogStore) -> None:
        self.pipeline = pipeline
        self.catalog = catalog

    @staticmethod
    def _content_version(stat_result: os.stat_result) -> str:
        return f"{stat_result.st_size}:{int(stat_result.st_mtime * 1000)}"

    def refresh(self, roots: list[str]) -> dict[str, Any]:
        summary: dict[str, Any] = {
            "scanned_files": 0,
            "indexed": 0,
            "skipped": 0,
            "unsupported": 0,
            "failed": 0,
        }
        for root in roots:
            if not os.path.isdir(root):
                continue
            for dirpath, _, filenames in os.walk(root):
                for filename in filenames:
                    file_path = os.path.join(dirpath, filename)
                    mime_type = mime_for_extension(filename)
                    if mime_type is None:
                        summary["unsupported"] += 1
                        continue
                    try:
                        stat_result = os.stat(file_path)
                    except OSError:
                        summary["failed"] += 1
                        continue
                    # Development-only local URI. Production Android scanning must
                    # receive a user-authorised SAF/MediaStore content URI.
                    source_uri = f"file://{file_path}"
                    content_version = self._content_version(stat_result)
                    summary["scanned_files"] += 1
                    if self.catalog.is_indexed(source_uri, None, content_version):
                        summary["skipped"] += 1
                        continue
                    result = self.pipeline.process_source(
                        source_uri=source_uri,
                        display_name=filename,
                        mime_type=mime_type,
                        file_path=file_path,
                        modified_at=int(stat_result.st_mtime * 1000),
                    )
                    if result.status == "indexed" and result.records:
                        record = result.records[0]
                        self.catalog.upsert_row(
                            {
                                "index_id": record.identifier,
                                "source_uri": source_uri,
                                "display_name": record.display_name,
                                "mime_type": record.mime_type,
                                "content_type": record.content_type,
                                "page": record.page,
                                "content_version": content_version,
                                "modified_at": record.modified_at,
                                "ocr_confidence": record.ocr_confidence,
                                "indexed_at": int(time.time() * 1000),
                                "transcription": record.transcription,
                            },
                            flush=False,
                        )
                        summary["indexed"] += 1
                    elif result.status == "unchanged":
                        summary["skipped"] += 1
                    else:
                        summary["failed"] += 1
        self.catalog.flush()
        summary["csv_path"] = self.catalog.csv_path
        summary["total_rows"] = self.catalog.row_count
        return summary
