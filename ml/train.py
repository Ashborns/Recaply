#!/usr/bin/env python3
"""Train/export the Recaply action-item classifier.

Primary lab path: use Create ML's Text Classifier template if coremltools is not
installed. This script documents the Python path for a Mac with scikit-learn and
coremltools available.
"""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CSV_PATH = ROOT / "training_data.csv"
MODEL_OUT = ROOT.parent / "Recaply" / "Resources" / "Models" / "ActionItemClassifier.mlmodel"


def load_rows() -> tuple[list[str], list[str]]:
    texts: list[str] = []
    labels: list[str] = []
    with CSV_PATH.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            texts.append(row["text"])
            labels.append(row["label"])
    return texts, labels


def main() -> None:
    try:
        from sklearn.feature_extraction.text import TfidfVectorizer
        from sklearn.linear_model import LogisticRegression
        from sklearn.pipeline import Pipeline
        import coremltools as ct
    except ImportError as exc:
        raise SystemExit(
            "Missing dependency. On the lab Mac, install scikit-learn and "
            "coremltools or use Create ML's Text Classifier template instead."
        ) from exc

    texts, labels = load_rows()
    if not texts:
        raise SystemExit(f"No rows found in {CSV_PATH}. Run generate_data.py first.")

    pipeline = Pipeline([
        ("tfidf", TfidfVectorizer(ngram_range=(1, 2), min_df=1)),
        ("clf", LogisticRegression(max_iter=1000, class_weight="balanced")),
    ])
    pipeline.fit(texts, labels)

    # The exact conversion API depends on the lab Mac's coremltools version.
    # If this conversion fails, use Create ML with the same training_data.csv.
    mlmodel = ct.converters.sklearn.convert(pipeline)
    mlmodel.short_description = "Recaply sentence label classifier"
    mlmodel.input_description["input"] = "Sentence text"
    mlmodel.output_description["classLabel"] = "Predicted Recaply sentence label"

    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(MODEL_OUT))
    print(f"WROTE {MODEL_OUT}")


if __name__ == "__main__":
    main()
