"""Reference local text index and the contract for the Android adapter."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import asdict, dataclass
import re
from threading import RLock
from typing import Any, Protocol


TOKEN_PATTERN = re.compile(r"[\w-]+", re.UNICODE)


@dataclass(frozen=True)
class IndexedRecord:
    identifier: str
    source_uri: str
    display_name: str
    mime_type: str
    content_type: str
    transcription: str
    page: int | None = None
    ocr_confidence: float | None = None
class IndexStore(Protocol):
    """The small contract that Android AppSearch must implement."""
    def upsert(self, record: IndexedRecord) -> None: ...
    def search(self, query: str, limit: int = 20) -> list[dict[str, Any]]: ...


class LocalTextIndex:
    """Thread-safe, in-memory reference for the AppSearch-backed Android index."""

    def __init__(self) -> None:
        self._records: dict[str, IndexedRecord] = {}
        self._terms: dict[str, set[str]] = defaultdict(set)
        self._record_terms: dict[str, set[str]] = {}
        self._source_records: dict[tuple[str, int | None], str] = {}
        self._lock = RLock()

    @staticmethod
    def _tokens(text: str) -> set[str]:
        return {token.casefold() for token in TOKEN_PATTERN.findall(text)}
    def _remove_identifier(self, identifier: str) -> None:
        record = self._records.pop(identifier, None)
        if record is None:
            return
        for term in self._record_terms.pop(identifier, set()):
            self._terms[term].discard(identifier)
            if not self._terms[term]:
                del self._terms[term]
        source_key = (record.source_uri, record.page)
        if self._source_records.get(source_key) == identifier:
            del self._source_records[source_key]

    def upsert(self, record: IndexedRecord) -> None:
        if not record.identifier or not record.source_uri or not record.transcription.strip():
            raise ValueError("identifier, source_uri, and transcription are required")
        searchable_text = f"{record.display_name} {record.transcription}"
        terms = self._tokens(searchable_text)
        with self._lock:
            source_key = (record.source_uri, record.page)
            previous_identifier = self._source_records.get(source_key)
            if previous_identifier and previous_identifier != record.identifier:
                self._remove_identifier(previous_identifier)
            self._remove_identifier(record.identifier)
            self._records[record.identifier] = record
            self._record_terms[record.identifier] = terms
            self._source_records[source_key] = record.identifier
            for term in terms:
                self._terms[term].add(record.identifier)

    def search(self, query: str, limit: int = 20) -> list[dict[str, Any]]:
        query_terms = self._tokens(query)
        if not query_terms:
            return []
        scores: dict[str, int] = defaultdict(int)
        with self._lock:
            for query_term in query_terms:
                for term, identifiers in self._terms.items():
                    if term.startswith(query_term):
                        for identifier in identifiers:
                            scores[identifier] += 1
            results = []
            for identifier, score in scores.items():
                record = self._records[identifier]
                if query.casefold() in record.transcription.casefold():
                    score += len(query_terms)
                result = asdict(record)
                result["snippet"] = self._snippet(record.transcription, query)
                result["open_uri"] = record.source_uri
                result["score"] = score
                results.append(result)
        return sorted(results, key=lambda result: (-result["score"], result["display_name"]))[:limit]

    @staticmethod
    def _snippet(text: str, query: str, radius: int = 80) -> str:
        position = text.casefold().find(query.casefold())
        if position < 0:
            return text[: radius * 2].strip()
        start = max(0, position - radius)
        end = min(len(text), position + len(query) + radius)
        return text[start:end].strip()
