#!/usr/bin/env python3
"""Generate a starter CSV for the Recaply sentence classifier.

This script intentionally avoids network calls so it can run anywhere. For the
final lab model, expand this CSV with AI-generated or hand-labeled examples to
~50-100 rows per class before training.
"""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "training_data.csv"

EXAMPLES = {
    "action_item": [
        "Please send the updated proposal by Friday.",
        "I will schedule the next meeting with the design team.",
        "Ash needs to export the screenshots for the report.",
        "Let's ask Kevin to review the transcript tomorrow.",
        "We should upload the final demo video tonight.",
        "Can you prepare the CoreML dataset before lab?",
        "The backend team should confirm the API key format.",
        "I will clean up the slides after class.",
    ],
    "decision": [
        "We decided to use local Core Data storage for version one.",
        "The team agreed that camera recording is optional.",
        "We will keep the cinematic dark interface.",
        "The deadline remains July first.",
        "We chose on-device speech recognition for privacy.",
        "The summary screen will open after processing finishes.",
        "We are not adding cloud sync in this release.",
        "The classifier will use four sentence categories.",
    ],
    "question": [
        "Can we finish the Xcode build before the lab closes?",
        "What should happen if the API key is missing?",
        "Do we need to support lecture and meeting modes?",
        "How long can the speech recognizer process one file?",
        "Should the polished transcript keep timestamps?",
        "Where do we store checked action items?",
        "Is the CoreML model required for the first demo?",
        "Can the user turn off camera while recording?",
    ],
    "discussion": [
        "The app shows a waveform while recording audio.",
        "Core Data stores recordings, transcripts, and summaries locally.",
        "The library screen highlights the newest session first.",
        "Speech recognition produces timestamped transcript fragments.",
        "The design uses purple and cyan accents on a dark background.",
        "The detail screen includes clean, polished, and raw transcript modes.",
        "A fallback classifier keeps the app running before training.",
        "The implementation is authored on WSL and built later in Xcode.",
    ],
}


def main() -> None:
    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["text", "label"])
        for label, rows in EXAMPLES.items():
            for text in rows:
                writer.writerow([text, label])
    print(f"WROTE {OUT} ({sum(len(v) for v in EXAMPLES.values())} examples)")


if __name__ == "__main__":
    main()
