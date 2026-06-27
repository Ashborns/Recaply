# Recaply iOS — Tasks

Status: ⬜ TODO · 🔄 IN PROGRESS · ✅ AUTHORED · ⬜ TODO LAB

## Tahap 0 — Scaffold (Agent 0)
- ✅ AUTHORED Struktur folder + domain value types
- ✅ AUTHORED Design tokens + date/time helpers
- ✅ AUTHORED Core Data stack + `Recaply.xcdatamodeld`
- ✅ AUTHORED App shell + `Info.plist`
- ✅ AUTHORED `gen_pbxproj.py` app target + `RecaplyTests` target, no SPM
- ✅ AUTHORED `.agents/*` + task board

## Agent 1 — Capture
- ✅ AUTHORED `RecordingService` (AVAudioEngine `.m4a`, RMS waveform, tap-format fix)
- ✅ AUTHORED `CameraService` (`AVCaptureSession` `.mp4`, async start, finalization wait)
- ✅ AUTHORED `RecordViewModel` + `RecordView` (Meeting/Lecture, title, waveform, haptics, camera toggle)
- ✅ AUTHORED `RecordViewModelTests`

## Agent 2 — Transcription
- ✅ AUTHORED `TranscriptionService` (`SFSpeechRecognizer` + URL request, on-device preference)
- ✅ AUTHORED `TranscriptSegmenter` + `TranscriptSegmenterTests`
- ⬜ TODO LAB Validate long recordings and add/rework split windows if needed

## Agent 3 — CoreML classifier
- ✅ AUTHORED `ClassificationService` + `ActionItemClassifier.swift` stub fallback
- ✅ AUTHORED `ClassificationServiceTests`
- ✅ AUTHORED `ml/generate_data.py` + `ml/train.py`
- ⬜ TODO LAB Train/drop `Resources/Models/ActionItemClassifier.mlmodel`, then flip provider from stub to real wrapper

## Agent 4 — LLM + Settings
- ✅ AUTHORED `KeychainStore`
- ✅ AUTHORED `LLMClient` GLM + `DeepseekClient` fallback
- ✅ AUTHORED `PromptBuilder`, enhancement/summarization services, JSON decoding tests
- ✅ AUTHORED `SettingsViewModel` + `SettingsView`

## Agent 5 — Storage + UI
- ✅ AUTHORED `RecordingRepository` Core Data bridge
- ✅ AUTHORED `PipelineCoordinator` 4-stage pipeline + `ProcessingStageView`
- ✅ AUTHORED Record → Processing pipeline handoff
- ✅ AUTHORED `LibraryView` + `LibraryViewModel`
- ✅ AUTHORED `RecordingDetailView` + `RecordingDetailViewModel` + `PlaybackController`
- ✅ AUTHORED Clean / Polished / Raw transcript modes + tap-to-seek

## Verifikasi Lab (Mac)
- ⬜ TODO LAB Buka `Recaply.xcodeproj` di Xcode 14.3.1
- ⬜ TODO LAB Build target `Recaply` ke simulator iOS 16.4
- ⬜ TODO LAB Run target `RecaplyTests` (5+ test files)
- ⬜ TODO LAB Record → Stop → Processing → Detail end-to-end
- ⬜ TODO LAB Set GLM key, verify enhancement + summary JSON
- ⬜ TODO LAB Train/drop `.mlmodel` atau lanjut dengan stub jika waktu mepet
- ⬜ TODO LAB Screenshot/demo video untuk laporan
