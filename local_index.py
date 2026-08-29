"""Reference local vector text index and the contract for the Android adapter."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import math
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
    modified_at: int | None = None


class IndexStore(Protocol):
    """The contract that the local index implementation must adhere to."""
    def upsert(self, record: IndexedRecord) -> None: ...
    def search(self, query: str, limit: int = 20) -> list[dict[str, Any]]: ...


@dataclass
class _VectorEntry:
    """Internal entry holding an indexed record and its sparse normalized feature vector."""
    record: IndexedRecord
    vector: dict[str, float]
    norm: float


class LocalTextIndex:
    """Thread-safe vector-based index storing all entries in a single list.
    
    Designed as a self-contained black box implementing IndexStore so that the underlying
    vector computation or storage engine can be swapped seamlessly.
    """

    def __init__(self) -> None:
        self._entries: list[_VectorEntry] = []
        self._lock = RLock()

    @staticmethod
    def _extract_terms(text: str) -> list[str]:
        tokens = [t.casefold() for t in TOKEN_PATTERN.findall(text)]
        terms: list[str] = list(tokens)
        for tok in tokens:
            if len(tok) > 3:
                for i in range(len(tok) - 2):
                    terms.append(tok[i:i + 3])
        return terms

    @classmethod
    def _vectorize(cls, text: str) -> tuple[dict[str, float], float]:
        terms = cls._extract_terms(text)
        if not terms:
            return {}, 0.0
        counts: dict[str, float] = {}
        for term in terms:
            counts[term] = counts.get(term, 0.0) + 1.0
        norm = math.sqrt(sum(v * v for v in counts.values()))
        if norm > 0.0:
            for k in counts:
                counts[k] /= norm
        return counts, norm

    @staticmethod
    def _cosine_similarity(vec1: dict[str, float], vec2: dict[str, float]) -> float:
        if not vec1 or not vec2:
            return 0.0
        if len(vec1) > len(vec2):
            vec1, vec2 = vec2, vec1
        return sum(val * vec2.get(key, 0.0) for key, val in vec1.items())

    def upsert(self, record: IndexedRecord) -> None:
        if not record.identifier or not record.source_uri or not record.transcription.strip():
            raise ValueError("identifier, source_uri, and transcription are required")
        
        searchable_text = f"{record.display_name} {record.transcription}"
        vector, norm = self._vectorize(searchable_text)
        new_entry = _VectorEntry(record=record, vector=vector, norm=norm)

        with self._lock:
            # Replace stale records for the same source URI and page, or matching identifier
            filtered_entries: list[_VectorEntry] = []
            for entry in self._entries:
                same_source = (entry.record.source_uri == record.source_uri and entry.record.page == record.page)
                same_id = (entry.record.identifier == record.identifier)
                if not (same_source or same_id):
                    filtered_entries.append(entry)
            
            filtered_entries.append(new_entry)
            self._entries = filtered_entries

    def search(self, query: str, limit: int = 20) -> list[dict[str, Any]]:
        query_text = query.strip()
        if not query_text:
            return []
        
        query_vec, query_norm = self._vectorize(query_text)
        query_tokens = {t.casefold() for t in TOKEN_PATTERN.findall(query_text)}
        
        scored: list[tuple[float, IndexedRecord]] = []
        with self._lock:
            for entry in self._entries:
                rec = entry.record
                sim = self._cosine_similarity(query_vec, entry.vector)
                
                # Check for prefix or exact matches in searchable text
                text_lower = f"{rec.display_name} {rec.transcription}".casefold()
                exact_boost = 1.0 if query_text.casefold() in text_lower else 0.0
                prefix_matches = sum(1 for term in entry.vector if any(term.startswith(qt) for qt in query_tokens))
                
                total_score = (sim * 2.0) + exact_boost + (prefix_matches * 0.2)
                if total_score > 0.0:
                    scored.append((total_score, rec))

        scored.sort(key=lambda item: (-item[0], item[1].display_name))
        
        results: list[dict[str, Any]] = []
        for score, rec in scored[:limit]:
            res = asdict(rec)
            res["snippet"] = self._snippet(rec.transcription, query_text)
            res["open_uri"] = rec.source_uri
            res["score"] = round(score, 4)
            results.append(res)
        return results

    @staticmethod
    def _snippet(text: str, query: str, radius: int = 80) -> str:
        position = text.casefold().find(query.casefold())
        if position < 0:
            return text[: radius * 2].strip()
        start = max(0, position - radius)
        end = min(len(text), position + len(query) + radius)
        return text[start:end].strip()
