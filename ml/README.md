# Recaply CoreML Training Data

This folder prepares the dataset for the Create ML Text Classifier used by
`ActionItemClassifier.mlmodel`.

## Dataset

Run:

```bash
python3 ml/build_training_data.py
```

The script downloads real public text corpora into `ml/raw/` and writes:

```text
ml/training_data.csv
```

The CSV has the exact Create ML format:

```csv
text,label
"Please review the proposal.",action_item
```

Current target labels:

- `action_item`
- `decision`
- `question`
- `discussion`

## Public Sources

- QMSum, meeting transcript benchmark: `https://github.com/Yale-LILY/QMSum`
- MeetingBank, public meeting transcripts/minutes: `https://huggingface.co/datasets/huuuyeah/meetingbank`
- DialogSum, dialogue summarization corpus: `https://huggingface.co/datasets/knkarthick/dialogsum`

The default fast path uses MeetingBank + DialogSum because they download
reliably on lab Wi-Fi. QMSum remains documented as an additional real meeting
source if more training data is needed.

## Labeling Method

The source sentences are real public dataset text. Labels are weak-supervision
rules for the four Recaply classes. Before final export, review the CSV in
Create ML or Numbers and fix obvious label mistakes, especially `action_item`
versus `question`.

## Create ML Steps

1. Open Xcode, then `Xcode > Open Developer Tool > Create ML`.
2. Create a new `Text Classifier` project.
3. Import `ml/training_data.csv`.
4. Set the text column to `text` and the label column to `label`.
5. Train, then export the model as `ActionItemClassifier.mlmodel`.
6. Put it at `Recaply/Resources/Models/ActionItemClassifier.mlmodel`.
7. Regenerate/open the Xcode project so the `.mlmodel` is included in the app target.
