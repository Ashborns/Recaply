#!/usr/bin/env python3
"""Build a real public-corpus CSV for Recaply's Create ML text classifier.

Output: ml/training_data.csv with columns: text,label
Labels: action_item, decision, question, discussion

Sources used:
- QMSum public meeting transcripts (GitHub: Yale-LILY/QMSum)
- MeetingBank public local-government meetings/minutes (Hugging Face: huuuyeah/meetingbank)
- DialogSum public dialogue data (Hugging Face: knkarthick/dialogsum)

The source sentences are real public dataset text. Labels are weak-supervision
rules, then capped/balanced for Create ML. For the final submission, manually
review the CSV in Create ML and correct obvious weak-label mistakes.
"""

from __future__ import annotations

import csv
import json
import random
import re
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parent
RAW_DIR = ROOT / "raw"
OUT = ROOT / "training_data.csv"
TARGET_PER_LABEL = 90
RANDOM_SEED = 27

QMSUM_URLS = [
    # Use the smaller split first so deadline-time generation finishes quickly.
    "https://raw.githubusercontent.com/Yale-LILY/QMSum/main/data/ALL/jsonl/val.jsonl",
    "https://raw.githubusercontent.com/Yale-LILY/QMSum/main/data/ALL/jsonl/test.jsonl",
]
DIALOGSUM_URLS = [
    "https://huggingface.co/datasets/knkarthick/dialogsum/resolve/main/validation.csv",
    "https://huggingface.co/datasets/knkarthick/dialogsum/resolve/main/test.csv",
]
MEETINGBANK_URLS = [
    "https://huggingface.co/datasets/huuuyeah/meetingbank/resolve/main/validation.json",
    "https://huggingface.co/datasets/huuuyeah/meetingbank/resolve/main/test.json",
]

LABELS = ["action_item", "decision", "question", "discussion"]

ACTION_PATTERNS = [
    r"\b(action item|to-do|todo|follow up|next step|assigned to)\b",
    r"^(please|can you|could you|make sure to|remember to)\b",
    r"\b(need to|needs to|should|must)\s+(send|prepare|review|schedule|share|upload|create|write|check|confirm|call|email|bring|submit|update|draft|collect|finish|complete|deliver|record|test|verify|ask|contact|provide|read)\b",
    r"\b(i|we|you|they|he|she)\s+(will|shall)\s+(send|prepare|review|schedule|share|upload|create|write|check|confirm|call|email|bring|submit|update|draft|collect|finish|complete|deliver|record|test|verify|ask|contact|provide|read)\b",
]
DECISION_PATTERNS = [
    r"\b(we|they|committee|council|board|team)\s+(decided|agreed|approved|adopted|resolved|voted|passed|selected|chose)\b",
    r"\b(decided to|agreed to|agreed that|approved filing|approved this|adopted the|resolved to|voted to|passed the|we chose)\b",
    r"\b(motion carried|ordinance approved|bill approved|committee approved|council approved|final choice)\b",
]
QUESTION_PATTERNS = [
    r"\?$",
]
DISCUSSION_NEGATIVE_PATTERNS = ACTION_PATTERNS + DECISION_PATTERNS + QUESTION_PATTERNS


@dataclass(frozen=True)
class Candidate:
    text: str
    label: str
    source: str


def download(url: str, name: str) -> Path:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    path = RAW_DIR / name
    if path.exists() and path.stat().st_size > 0:
        return path
    print(f"Downloading {url}")
    with urllib.request.urlopen(url, timeout=60) as response, path.open("wb") as f:
        while True:
            chunk = response.read(1024 * 256)
            if not chunk:
                break
            f.write(chunk)
    return path


def clean_text(text: str) -> str:
    text = re.sub(r"#Person\d+#:\s*", "", text)
    text = re.sub(r"\s+", " ", text)
    text = text.replace(" ,", ",").replace(" .", ".")
    return text.strip().strip('"')


def split_sentences(text: str) -> list[str]:
    text = clean_text(text)
    pieces = re.split(r"(?<=[.!?])\s+", text)
    out: list[str] = []
    for piece in pieces:
        sentence = clean_text(piece)
        words = sentence.split()
        if 5 <= len(words) <= 32 and not sentence.startswith(("http", "www")):
            out.append(sentence)
    return out


def matches(patterns: list[str], text: str) -> bool:
    lowered = text.lower()
    return any(re.search(pattern, lowered) for pattern in patterns)


def weak_label(sentence: str) -> str | None:
    if matches(QUESTION_PATTERNS, sentence):
        return "question"
    if matches(DECISION_PATTERNS, sentence):
        return "decision"
    if matches(ACTION_PATTERNS, sentence):
        return "action_item"
    if not matches(DISCUSSION_NEGATIVE_PATTERNS, sentence):
        return "discussion"
    return None


def qmsum_candidates() -> Iterable[Candidate]:
    for idx, url in enumerate(QMSUM_URLS):
        path = download(url, f"qmsum_{idx}.jsonl")
        with path.open(encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                item = json.loads(line)
                for turn in item.get("meeting_transcripts", []):
                    for sentence in split_sentences(turn.get("content", "")):
                        label = weak_label(sentence)
                        if label:
                            yield Candidate(sentence, label, "QMSum")


def dialogsum_candidates() -> Iterable[Candidate]:
    for idx, url in enumerate(DIALOGSUM_URLS):
        path = download(url, f"dialogsum_{idx}.csv")
        with path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                for sentence in split_sentences(row.get("dialogue", "")):
                    label = weak_label(sentence)
                    if label:
                        yield Candidate(sentence, label, "DialogSum")


def meetingbank_candidates() -> Iterable[Candidate]:
    for idx, url in enumerate(MEETINGBANK_URLS):
        path = download(url, f"meetingbank_{idx}.json")
        raw = path.read_text(encoding="utf-8")
        decoder = json.JSONDecoder()
        pos = 0
        while pos < len(raw):
            while pos < len(raw) and raw[pos].isspace():
                pos += 1
            if pos >= len(raw):
                break
            item, pos = decoder.raw_decode(raw, pos)
            for field in ("summary", "transcript", "meeting", "text"):
                value = item.get(field) if isinstance(item, dict) else None
                if isinstance(value, str):
                    for sentence in split_sentences(value):
                        label = weak_label(sentence)
                        if label:
                            yield Candidate(sentence, label, "MeetingBank")


def build() -> list[Candidate]:
    random.seed(RANDOM_SEED)
    buckets: dict[str, list[Candidate]] = {label: [] for label in LABELS}
    seen: set[str] = set()

    # QMSum is a good extra meeting source, but its raw files can be slow on lab Wi-Fi.
    # Keep the deadline path fast: MeetingBank + DialogSum already provide real public text.
    for candidate in list(meetingbank_candidates()) + list(dialogsum_candidates()):
        normalized = candidate.text.lower()
        if normalized in seen:
            continue
        seen.add(normalized)
        if candidate.label in buckets:
            buckets[candidate.label].append(candidate)

    for label in LABELS:
        random.shuffle(buckets[label])
        print(f"{label}: found {len(buckets[label])}, using {min(TARGET_PER_LABEL, len(buckets[label]))}")

    selected: list[Candidate] = []
    for label in LABELS:
        selected.extend(buckets[label][:TARGET_PER_LABEL])
    random.shuffle(selected)
    return selected


def main() -> None:
    selected = build()
    counts = {label: 0 for label in LABELS}
    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["text", "label"])
        for row in selected:
            counts[row.label] += 1
            writer.writerow([row.text, row.label])

    print(f"WROTE {OUT} ({len(selected)} rows)")
    print(counts)
    print("Review weak labels before final Create ML export if time permits.")


if __name__ == "__main__":
    main()
