# SHARED STATE — Recaply iOS Multi-Agent Build

Status board pengembangan Recaply iOS oleh 6 AI agent. Marker: ⬜ TODO · 🔄 IN PROGRESS · ✅ AUTHORED · ❌ BLOCKED

> Catatan: kode sudah ditulis di WSL. Semua status ✅ AUTHORED berarti source + pbxproj sudah dibuat dan quick gate lulus. Status final ✅ STABLE baru setelah build/test di lab Mac Xcode 14.3.1.

## Pembagian Agent

| Agent | Peran | File yang dimiliki |
|-------|------|--------------------|
| **0 — Architect** | Scaffold, tokens, Core Data stack, pbxproj, Info.plist | `App/*`, `Core/Extensions`, `Core/Data/PersistenceController.swift`, `Recaply.xcdatamodeld`, `gen_pbxproj.py`, `Info.plist` |
| **1 — Capture** | Rekaman mic + kamera, waveform | `RecordingService`, `CameraService`, `Features/Record/*` |
| **2 — Transcription** | Speech-to-text on-device + segmentasi | `TranscriptionService`, `TranscriptSegmenterTests` |
| **3 — CoreML** | Classifier teks + stub fallback + training scripts | `ClassificationService`, `ActionItemClassifier.swift`, `ml/*` |
| **4 — LLM** | Enhancement + summarization, prompt, JSON, Keychain, Settings | `LLMClient`, `DeepseekClient`, `KeychainStore`, `TranscriptEnhancementService`, `SummarizationService`, `Features/Settings/*` |
| **5 — Storage + UI** | Repository, pipeline, Library, Detail, playback | `RecordingRepository`, `PipelineCoordinator`, `ProcessingStageView`, `Features/Library/*`, `Features/Detail/*` |

## Kontrak Bersama

- `RecordingInfo { id, title?, tag, createdAt, duration, audioURL?, videoURL?, status }`
- `TranscriptSegmentModel { id, index, text, timestamp, label, confidence }`
- `SentenceLabel { action_item, decision, question, discussion }`
- `SessionTag { meeting, lecture }`
- `PipelineStatus { captured, transcribing, classifying, enhancing, summarizing, ready, failed }`
- `SummaryPayload { overview, actionItems, decisions, keyPoints }`
- `EnhancedTranscriptPayload { clean: [CleanSegment{index,text}], polished: [TopicSection{heading,body}] }`
- Service protocols: `RecordingProviding`, `CameraProviding`, `TranscriptionProviding`, `ClassificationProviding`, `LLMProviding`.

## Status Build

| Komponen | Agent | Status |
|----------|-------|--------|
| Scaffold + `gen_pbxproj.py` + app/test target | 0 | ✅ AUTHORED |
| `Info.plist`, tokens, Core Data model, domain types | 0 | ✅ AUTHORED |
| `RecordingService` + `CameraService` + waveform | 1 | ✅ AUTHORED |
| `Features/Record/*` capture UI + ViewModel | 1 | ✅ AUTHORED |
| `TranscriptionService` + `TranscriptSegmenterTests` | 2 | ✅ AUTHORED |
| `ClassificationService` + `ActionItemClassifier` + stub | 3 | ✅ AUTHORED |
| `ml/generate_data.py` + `ml/train.py` | 3 | ✅ AUTHORED |
| `.mlmodel` trained model | 3 | ⬜ TODO LAB |
| `LLMClient`, `DeepseekClient`, `KeychainStore` | 4 | ✅ AUTHORED |
| `TranscriptEnhancementService` + `SummarizationService` | 4 | ✅ AUTHORED |
| `Features/Settings/*` | 4 | ✅ AUTHORED |
| `RecordingRepository` Core Data bridge | 5 | ✅ AUTHORED |
| `PipelineCoordinator` + `ProcessingStageView` | 5 | ✅ AUTHORED |
| `Features/Library/*` | 5 | ✅ AUTHORED |
| `Features/Detail/*` + `PlaybackController` | 5 | ✅ AUTHORED |
| XCTest suite (5+ files) | semua | ✅ AUTHORED |
| Xcode build + XCTest run | semua | ⬜ TODO LAB |

## Catatan Koordinasi

- Build/test belum bisa dijalankan di WSL. Tugas lab pertama: buka `Recaply.xcodeproj` di Xcode 14.3.1, build target `Recaply`, lalu run `RecaplyTests`.
- Core Data optional policy: atribut boleh optional di model, tapi repository default ke `""`/`[]` saat baca.
- `EnhancedTranscript.clean` disimpan ke `TranscriptSegment.cleanedText`; `EnhancedTranscript.polished` disimpan sebagai `polishedJSON`.
- `CameraService.stop()` mengembalikan URL segera; kalau Phase 5 butuh video file, panggil `await camera.waitForFinalization()` sebelum membaca video.
- `ClassificationService.shared` masih memakai stub sampai `.mlmodel` dilatih di lab.
