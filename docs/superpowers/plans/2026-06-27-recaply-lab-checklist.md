# Recaply — Lab Verification Checklist

**Context:** Source was authored on WSL/Linux. Final compile, XCTest, speech, camera, CoreML model, and device permissions must be verified on a Mac with Xcode 14.3.1 and iOS 16.4 simulator/device.

## 0. Before opening Xcode

```bash
cd /mnt/c/dev/recaply
python3 gen_pbxproj.py
git status
```

Expected:
- `swift=37 resources=0 bundles=1`
- `git status` clean

## 1. Open and build

1. Open `Recaply.xcodeproj` in Xcode 14.3.1.
2. Select target `Recaply`.
3. Select an iOS 16.4 simulator.
4. Build.

If build fails, fix in this priority order:
1. `project.pbxproj` / target membership.
2. Swift compile errors from framework API signatures.
3. Core Data model/entity naming.
4. UI polish issues last.

## 2. Run tests

Run target `RecaplyTests`.

Expected test files:
- `RecaplyTestsPlaceholder.swift`
- `RecordViewModelTests.swift`
- `TranscriptSegmenterTests.swift`
- `ClassificationServiceTests.swift`
- `PromptBuilderTests.swift`
- `EnhancementDecodingTests.swift`

If test target cannot attach, inspect `Recaply.xcodeproj/project.pbxproj` test target settings:
- `productType = "com.apple.product-type.bundle"`
- `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Recaply.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Recaply"`
- `BUNDLE_LOADER = "$(TEST_HOST)"`

## 3. Manual app smoke test

1. Launch app.
2. Open **Record** tab.
3. Grant microphone and speech permissions.
4. Record a 10–20 second meeting-style clip.
5. Stop.
6. Confirm Processing screen appears and stages advance.
7. Open Library.
8. Open latest recording detail.
9. Test:
   - Clean transcript
   - Polished transcript
   - Raw transcript
   - Tap transcript segment to seek audio
   - Playback bar play/pause/slider

## 4. API key test

1. Open **Settings**.
2. Add GLM key, optionally Deepseek key.
3. Save.
4. Record another short clip.
5. Confirm summary/enhancement appears.

If no key is available, expected behavior:
- Transcription and classification still work.
- Enhancement falls back to raw text.
- Summary may be missing gracefully.

## 5. CoreML lab path

Fast route if deadline is tight:
- Keep stub classifier. It returns `discussion`/`0`, app still runs.

Better route if time allows:

```bash
cd ml
python3 generate_data.py
python3 train.py
cd ..
python3 gen_pbxproj.py
```

Then add `Recaply/Resources/Models/ActionItemClassifier.mlmodel` and switch `ClassificationService.shared` from `StubClassifierProvider()` to `CoreMLClassifierProvider.shared` after confirming the generated model wrapper API.

## 6. Demo video checklist

Record these for the report:
- Multi-agent/task board commit history.
- App launch with cinematic tabs.
- Record screen waveform.
- Processing 4-stage screen.
- Library hero card.
- Detail screen with Summary + Clean/Polished/Raw.
- Tap-to-seek audio.
- Settings API-key page.

## 7. Known deferred validation

- Long speech-recognition recordings may need split-window restart logic after lab testing.
- `.mlmodel` is optional if deadline is too tight, because stub fallback is built in.
- Build/test result must be reported honestly in the final report.
