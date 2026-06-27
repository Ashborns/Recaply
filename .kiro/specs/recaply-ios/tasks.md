# Recaply iOS — Tasks

Tickets berurutan, dikelompokkan per agent. Status: ⬜ TODO · 🔄 IN PROGRESS · ✅ DONE
Spesifikasi: `docs/superpowers/specs/2026-06-27-recaply-design.md`.

## Tahap 0 — Scaffold (Agent 0 — Architect)
- 🔄 Struktur folder (App/Core/Features/Resources) + domain value types `Core/Models/*`
- 🔄 Design tokens `Core/Extensions/Color+Theme.swift` + `Date+` + `TimeInterval+`
- 🔄 Core Data stack `PersistenceController` + `Recaply.xcdatamodeld` (4 entity + relasi)
- 🔄 App shell: `RecaplyApp`, `RootView`, `MainTabView`
- 🔄 `Info.plist` (mic + camera + speech usage strings, no background mode)
- 🔄 `gen_pbxproj.py` (app target + `RecaplyTests` test target, no SPM) + `project.pbxproj`
- 🔄 `.agents/*` + `.kiro/specs/recaply-ios/tasks.md`
- ⬜ **Verifikasi lab pertama**: buka di Xcode 14.3.1, build `Recaply` + `RecaplyTests` ke simulator iOS 16.4 (gate sebelum polish)

## Agent 1 — Capture (mic + kamera)
- ⬜ `RecordingService` (AVAudioEngine, file `.m4a`, state machine `idle → recording → stopping`, haptic start/stop)
- ⬜ `CameraService` (AVCaptureSession → `.mp4`, toggle on/off)
- ⬜ `Features/Record/RecordViewModel` + `RecordView` (tag Meeting/Lecture, nama opsional, waveform live, tombol record/stop)
- ⬜ On Stop → tulis `Recording` (Core Data) → navigasi ke Processing

## Agent 2 — Transcription (on-device speech)
- ⬜ `TranscriptionService` (`SFSpeechRecognizer` pada file audio → segmen bertimestamp)
- ⬜ Logika task-restart untuk rekaman > 1 menit (konkatenasi hasil)
- ⬜ Segmentasi kalimat → `[TranscriptSegmentModel]`; fallback kalau transkrip kosong
- ⬜ Unit test `TranscriptSegmenterTests` (split + timestamp)

## Agent 3 — CoreML classifier
- ⬜ `ClassificationService` (klasifikasi per segmen → `{label, confidence}`)
- ⬜ `ActionItemClassifier.swift` wrapper + **stub fallback** (`discussion`/0 saat model absen)
- ⬜ Train classifier teks 4-kelas (Create ML / coremltools) di lab → `Resources/Models/ActionItemClassifier.mlmodel`
- ⬜ Unit test `ClassificationServiceTests` (stub + model)
- ⬜ Daftarkan `.mlmodel` ke resource (re-run `gen_pbxproj.py`)

## Agent 4 — LLM (enhance + summarize)
- ⬜ `LLMClient` (GLM, `URLSession`, `/v1/chat/completions`, `response_format: json_object`, timeout 30s + 1 retry)
- ⬜ `DeepseekClient` (fallback provider)
- ⬜ `KeychainStore` (simpan/validasi API key, jangan commit credential)
- ⬜ `TranscriptEnhancementService` (1 call → `EnhancedTranscriptPayload` clean + polished; fallback raw)
- ⬜ `SummarizationService` (1 call → `SummaryPayload`; fallback no-summary + notice)
- ⬜ `Features/Settings/SettingsViewModel` + `SettingsView` (key GLM/Deepseek, toggle speech, model pick, About)
- ⬜ Unit test `PromptBuilderTests` + `EnhancementParsingTests`

## Agent 5 — Storage + UI (Library / Detail / Processing / playback)
- ⬜ Entity extensions `Core/Data/Models/*` + mapping Core Data ↔ domain (`RecordingInfo`, dll)
- ⬜ Pipeline orchestrator: Transcribe → Classify → Enhance → Summarize, update `Recording.status` tiap stage, retryable
- ⬜ Processing screen (4 stage nyala berurutan + haptic tick + auto-nav ke Detail)
- ⬜ `Features/Library/*` (hero card terbaru + compact rows + empty state; Library row mirror progress)
- ⬜ `Features/Detail/*` (summary card color-coded + action item checkable; transcript Clean/Polished/Raw; tap-to-seek)
- ⬜ Floating glass playback bar (play/pause + scrubber accent gradient + glow + time)
- ⬜ Unit test `RecordViewModelTests` (state machine capture)

## Verifikasi Lab (di Mac, gate pertama = build Tahap 0)
- ⬜ Buka `Recaply.xcodeproj` di Xcode 14.3.1
- ⬜ Build target `Recaply` ke simulator iOS 16.4 (validasi scaffold + Core Data + tema)
- ⬜ Build + run target `RecaplyTests` (smoke test)
- ⬜ Setelah semua agent selesai: alur Record → Stop → Processing → Detail end-to-end
- ⬜ Verifikasi 4-stage pipeline + Clean/Polished/Raw + tap-to-seek + action item checkable
- ⬜ 5+ XCTest lulus
- ⬜ Screenshot untuk demo video + laporan (seksi 8 multi-agent wajib tertulis)
