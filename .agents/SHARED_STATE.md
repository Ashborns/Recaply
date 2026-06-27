# SHARED STATE — Recaply iOS Multi-Agent Build

Status board pengembangan Recaply iOS oleh 6 AI agent. Tiap agent punya domain +
skill spesifik. Marker: ⬜ TODO · 🔄 IN PROGRESS · ✅ STABLE · ❌ BLOCKED

> Workflow: ambil ticket di `tasks.md` → implementasi di file milikmu → update status
> di sini → review silang → baru tandai ✅ STABLE. Kontrak bersama jangan diubah
> tanpa catat di sini.

## Pembagian Agent

| Agent | Peran | Skill / Domain | File yang dimiliki |
|-------|------|----------------|--------------------|
| **0 — Architect** | Scaffold, design tokens, Core Data stack, `gen_pbxproj.py`, `Info.plist` | pbxproj, MVVM, Core Data, tema | `App/*`, `Core/Extensions`, `Core/Data/PersistenceController.swift`, `Recaply.xcdatamodeld`, `gen_pbxproj.py`, `Info.plist` |
| **1 — Capture** | Rekaman mic + kamera, waveform | AVFoundation, AVAudioEngine, AVCaptureSession, file IO | `Core/Services/RecordingService`, `CameraService`, `Features/Record/*` |
| **2 — Transcription** | Speech-to-text on-device + segmentasi + task restart | Speech framework, `SFSpeechRecognizer`, async/await | `Core/Services/TranscriptionService`, tipe transcript di `Core/Models` |
| **3 — CoreML** | Train + integrasi classifier teks + stub fallback | Create ML / `coremltools`, CoreML | `Core/Services/ClassificationService`, `ActionItemClassifier.*`, `Resources/Models` |
| **4 — LLM** | Enhancement + summarization, prompt, JSON, Keychain, Settings | URLSession, OpenAI-compatible (GLM, Deepseek), Keychain | `Core/Services/SummarizationService`, `TranscriptEnhancementService`, `LLMClient`, `DeepseekClient`, `KeychainStore`, `Features/Settings/*` |
| **5 — Storage + UI** | Wiring Core Data, Library, Detail, Processing, playback | Core Data, SwiftUI list/detail, AVPlayer | `Core/Data/Models/*` entity extensions, `Features/Library/*`, `Features/Detail/*`, Processing screen, playback bar |

## Kontrak Bersama (jangan diubah diam-diam)

- `RecordingInfo { id, title?, tag, createdAt, duration, audioURL?, videoURL?, status }`
- `TranscriptSegmentModel { id, index, text, timestamp, label, confidence }`
- `SentenceLabel { action_item, decision, question, discussion }` (raw value string)
- `SessionTag { meeting, lecture }`
- `PipelineStatus { captured, transcribing, classifying, enhancing, summarizing, ready, failed }`
- `SummaryPayload { overview, actionItems, decisions, keyPoints }`
- `EnhancedTranscriptPayload { clean: [CleanSegment{index,text}], polished: [TopicSection{heading,body}] }`
- Service = singleton, constructor-injected (`.shared` default, overridable di test).
  Protokol service (akan didefinisikan per agent): `RecordingProviding`,
  `TranscriptionProviding`, `ClassificationProviding`, `LLMProviding`.
  (`SummarizationService` dan `TranscriptEnhancementService` = concrete singleton,
  bukan protokol.)

## Status Build

| Komponen | Agent | Status |
|----------|-------|--------|
| Scaffold + struktur folder | 0 | 🔄 IN PROGRESS |
| `gen_pbxproj.py` (app + test target, no SPM) | 0 | 🔄 IN PROGRESS |
| `Info.plist` (mic/camera/speech) | 0 | 🔄 IN PROGRESS |
| Design tokens `Color+Theme.swift` + `Date+` + `TimeInterval+` | 0 | 🔄 IN PROGRESS |
| Core Data stack `PersistenceController` | 0 | 🔄 IN PROGRESS |
| `Recaply.xcdatamodeld` (Recording/TranscriptSegment/EnhancedTranscript/Summary) | 0 | 🔄 IN PROGRESS |
| Domain value types (`Core/Models/*`) | 0 | 🔄 IN PROGRESS |
| App shell `RecaplyApp`/`RootView`/`MainTabView` | 0 | 🔄 IN PROGRESS |
| `RecordingService` + `CameraService` + waveform | 1 | 🔄 IN PROGRESS |
| `Features/Record/*` (capture UI + ViewModel) | 1 | 🔄 IN PROGRESS |
| `TranscriptionService` (SFSpeechRecognizer + restart) | 2 | ⬜ TODO |
| `ClassificationService` + `ActionItemClassifier` + stub | 3 | ⬜ TODO |
| `Resources/Models/ActionItemClassifier.mlmodel` (train di lab) | 3 | ⬜ TODO |
| `LLMClient` (GLM) + `DeepseekClient` + `KeychainStore` | 4 | ⬜ TODO |
| `TranscriptEnhancementService` + `SummarizationService` | 4 | ⬜ TODO |
| `Features/Settings/*` (API key, model pick) | 4 | ⬜ TODO |
| Entity extensions + mapping Core Data ↔ domain | 5 | ⬜ TODO |
| `Features/Library/*` (hero card + rows + empty state) | 5 | ⬜ TODO |
| `Features/Detail/*` (summary, transcript Clean/Polished/Raw, tap-to-seek) | 5 | ⬜ TODO |
| Processing screen + playback bar | 5 | ⬜ TODO |
| XCTest suite (5+ file) | semua | ⬜ TODO |

## Catatan Koordinasi
- Semua komponen Tahap 0 sudah ditulis tapi **belum diverifikasi build** (no Mac).
  Status baru ✅ STABLE setelah build lab sukses + review silang.
- `PersistenceController.shared` = titik tunggal Core Data (Agent 0). `viewContext`
  di-inject ke environment di `RecaplyApp`. Agent 5 baca lewat ini, jangan buat stack baru.
- Agent 5 "memiliki" `Core/Data/Models/*` (entity extensions + mapping). File
  `Recaply.xcdatamodeld` dan `PersistenceController` milik Agent 0 — koordinasi kalau
  perlu tambah entity/atribut.
- Klasifikasi CoreML: sebelum model trained, `ClassificationService` pakai stub yang
  return `discussion`/0 (design spec seksi 5 & 10).
- Core Data optional policy: atribut boleh `optional="YES"` di model, tapi domain value
  types memperlakukannya sebagai non-nil; repository default ke `""`/`[]` saat baca
  (sehingga `actionItemsJSON` nil decode ke `[]`).
- Lab-build gate: komponen Tahap 0 pindah 🔄 IN PROGRESS → ✅ STABLE hanya setelah
  build lab pertama sukses; Agent 1–5 boleh menulis di atas scaffold sekarang, tapi
  verifikasi compile ditunda ke lab (Tahap 6).
