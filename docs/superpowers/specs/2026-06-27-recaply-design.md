# Recaply — Design Spec

**Date:** 2026-06-27
**Author:** Ash (TheFool), Nanjing Xiaozhuang University (NXU)
**Course:** iOS Application Development, Final Project
**Deadline:** 2026-07-01
**Status:** Approved (design). Implementation pending.

> This design refines and supersedes the scope decisions in the PRD (`docs/superpowers/specs/2026-06-27-meeting-summarizer-prd.md`) where the two disagree. The PRD remains the source for toolchain constraints and the multi-agent roster. Read both before writing code.

---

## 0. Context and goal

Recaply is a native iOS app that records a meeting or lecture (microphone plus optional camera), transcribes it on-device, classifies each sentence with a custom CoreML model, runs a cloud LLM to produce both a **cleaned/polished transcript** and a **structured summary**, and presents the result through a cinematic, immersive UI. The deliverable is a fully functional app plus the multi-agent documentation and XCTest suite that feed the course report.

The app is authored on Linux/WSL without Xcode. Source is generated and committed here; the project file is emitted by `gen_pbxproj.py`; builds, CoreML training, and device runs happen at the iOS lab later.

---

## 1. Resolved decisions (locked)

1. **App:** Recaply, bundle id `cn.edu.njxzc.Recaply`.
2. **Aesthetic:** Cinematic AI (deep gradient canvas, glass surfaces, purple→cyan accent, spring motion, haptics). Unified across all screens.
3. **Capture:** microphone plus optional camera. No screen recording in v1.
4. **AI output is a 4-stage pipeline per recording:** Raw transcript → Clean → Polished → Summary.
5. **Transcript enhancement:** a single LLM call returns **both** the clean (timestamp-preserving) and polished (topic-segmented notes) versions.
6. **CoreML:** a custom text classifier, 4 classes (`action_item`, `decision`, `question`, `discussion`). Ships with a stub fallback.
7. **LLM:** GLM primary, Deepseek fallback, plain `URLSession`, OpenAI-compatible `/v1/chat/completions`.
8. **Storage:** Core Data, local only. No Firebase.
9. **UI:** SwiftUI, MVVM, `ObservableObject` + `@Published` (no `@Observable`).
10. **Category colors (system):** action_item `#FF9F0A`, decision `#30D158`, question `#0A84FF`, discussion `#8E8E93`.
11. **Build model:** 6 AI agents (see section 8), documented as the rubric demands.

---

## 2. Visual identity — Cinematic AI

Carries the discipline of the `noveldex-design` skill (token-driven, no magic numbers, grid, spring motion, respect `reduceMotion`) and the atmosphere/craft of `frontend-design`, adapted to a dark native iOS app.

### Tokens

| Token | Value | Use |
|---|---|---|
| Background base | vertical gradient `#0B0B14 → #000000` | App canvas |
| Surface (elevated) | glass over `.ultraThinMaterial`, fill `rgba(255,255,255,0.05)`, 1px hairline `rgba(255,255,255,0.09)` | Cards, sheets |
| Accent gradient | `#7B6CFF → #22D3EE` (purple→cyan) | CTAs, active states, scrubber, glow |
| Action | `#FF9F0A` | action_item category |
| Decision | `#30D158` | decision category |
| Question | `#0A84FF` | question category |
| Discussion | `#8E8E93` | discussion category |
| Text primary | `#FFFFFF` | Headings, body |
| Text secondary | `#C9C5DC` | Body muted |
| Text tertiary | `#8A85A8` | Captions, meta |

### Typography
- **SF Pro** (system). Display weight `.semibold`/`.bold`. Body `.regular`. Captions `.regular` at 12–13px.
- **Tabular numerics** (`monospacedDigit()`) for the timer, durations, and segment timestamps.
- Hierarchy via weight and color, not extra type sizes. Max 3–4 sizes per screen.

### Motion
- SwiftUI springs: `response ≈ 0.45`, `dampingFraction ≈ 0.8` for UI; snappier (`response ≈ 0.3`) for toggles.
- **Signature staggered reveal** on Detail open: overview → action items → decisions cascade in with small delays.
- Respect `@Environment(\.accessibilityReduceMotion)` — collapse to opacity-only when set.

### Haptics
- `UIImpactFeedbackGenerator(.medium)`: record start, record stop, each processing-stage transition, segment tap.
- `UIImpactFeedbackGenerator(.light)`: tag/segmented-control toggle, action-item checkbox.
- `UINotificationFeedbackGenerator(.success)`: pipeline complete.

### Depth & glass (iOS 16.4-safe)
- `.ultraThinMaterial` / `.regularMaterial` for the playback bar, tab bar, sheets, and elevated cards.
- Soft accent glow via `.shadow(color:radius:)` on accent elements (button, scrubber head, active category dots).

---

## 3. Navigation and screens

`MainTabView` — 3 glass bottom tabs: **Record · Library · Settings**, using `NavigationStack`.

### 3.1 Record (`Features/Record`)
Audio-first capture with a Meeting/Lecture tag.
- Segmented control **Meeting | Lecture** (drives the LLM prompt and Library grouping).
- Optional name field ("Name this session").
- Live audio waveform from `AVAudioEngine` input levels.
- Large record/stop button. **Camera toggle** (off by default; `AVCaptureSession` to `.mp4`).
- States: `idle → recording → stopping`. Haptic on start and stop.
- On Stop: write `Recording`, transition to the Processing screen.

### 3.2 Processing (full-screen, post-Stop)
The visible AI pipeline. Four stages light up in sequence with a spring animation and a haptic tick each:
1. **Transcribing** (Speech → text)
2. **Classifying** (CoreML labels)
3. **Enhancing** (LLM clean + polished)
4. **Summarizing** (LLM summary)

On completion, auto-navigate to Detail (`UINotificationFeedbackGenerator(.success)`). If the user leaves, the Library row mirrors live progress. Any stage that fails shows an inline error with **Retry** for that stage; the app never crashes.

### 3.3 Library (`Features/Library`)
- **Featured hero card** for the latest recording: title, tag, summary preview line, category counts (`● 3 ● 2 ● 1`), duration, and an **open-action-items strip**.
- **Compact rows** below for older recordings: title, tag, date, duration. Tap → Detail.
- Empty state when there are no recordings.

### 3.4 Detail (`Features/RecordingDetail`) — the money screen
- Header: title, tag, date, duration, segment count.
- **Summary card**: Overview, **Action items** (checkable rows), **Decisions**, **Key points** — all color-coded.
- **Transcript** section with a segmented control **Clean | Polished | Raw** (Clean default).
  - Clean / Raw: timestamped, category-dotted; **tap a segment → audio seeks to that timestamp**.
  - Polished: **topic-segmented notes** (heading + body per topic).
- **Floating glass playback bar**: play/pause, scrubber with accent gradient + glow, current/total time.

### 3.5 Settings (`Features/Settings`)
GLM API key (primary), Deepseek API key (fallback), on-device speech toggle, model pick, About. Keys in Keychain, validated on save, friendly empty/error states. Never force-unwrap.

---

## 4. The AI pipeline (per recording)

```
Stop ─► 1. Transcribe ─► 2. Classify ─► 3. Enhance ─► 4. Summarize ─► Detail
        (Speech,       (CoreML,       (LLM,         (LLM,
         on-device)     on-device)     cloud)        cloud)
```

Each stage updates `Recording.status`. Each stage is independently retryable and has a graceful degradation path.

1. **Transcribe** — `SFSpeechRecognizer` on the audio file → timestamped sentence segments. Recordings over the ~1-minute task limit are handled by task-restart logic that concatenates results.
2. **Classify** — CoreML text classifier on each segment → `{label, confidence}`. If the model is absent, return `discussion` with confidence 0 (stub).
3. **Enhance** — one LLM call. Input: segments with timestamps and labels. Output JSON:
   ```json
   {
     "clean": [ { "index": 0, "text": "..." } ],
     "polished": [ { "heading": "Scope", "body": "..." } ]
   }
   ```
   `clean` preserves order/timestamps (interactive). `polished` is topic-segmented notes. Fallback: `clean` = raw text per segment, `polished` = raw joined.
4. **Summarize** — one LLM call. Input: transcript plus labels. Output JSON:
   ```json
   {
     "overview": "...",
     "actionItems": ["..."],
     "decisions": ["..."],
     "keyPoints": ["..."]
   }
   ```
   Fallback: no summary, Detail shows transcript-only with a notice.

### LLM transport
`LLMClient` (GLM) and `DeepseekClient` (fallback) wrap `URLSession` against OpenAI-compatible `/v1/chat/completions`. Prefer `response_format: json_object` when supported; otherwise parse a fenced JSON block. Keys read from `KeychainStore`. A 30s timeout with one retry; on failure, fall back to the other provider, then to the per-stage degradation.

---

## 5. CoreML plan

- **Task:** single-label, multi-class text classification, 4 classes.
- **Training data:** ~200–400 labeled sentences, balanced. **Primary:** AI-generated synthetic sentences per class, exported `text,label` CSV. Fallbacks: hand-label real transcript sentences, or filter a public dialogue-act dataset.
- **Training (lab):** Create ML Text Classifier template (~30 min), or scikit-learn (TF-IDF + LogisticRegression) converted with `coremltools`.
- **Integration:** `Resources/Models/ActionItemClassifier.mlmodel` wrapped by `ActionItemClassifier.swift`. **Stub fallback** returns `discussion`/0 when the model is missing, so the app builds and runs before training.
- **Why text, not sound:** surfacing action items and decisions is the product's core value; sound classification (ESC-50) is peripheral and remains a stretch goal.

---

## 6. Data model (Core Data)

Entities (inverse relationships elided for brevity):

| Entity | Key attributes |
|---|---|
| `Recording` | `id: UUID`, `title: String?`, `tag: String`, `createdAt: Date`, `duration: Double`, `audioURL: String`, `videoURL: String?`, `status: String` (pipeline stage) |
| `TranscriptSegment` | `index: Int16`, `text: String`, `timestamp: Double`, `label: String`, `confidence: Double`, `cleanedText: String?`, `recording ←→` |
| `EnhancedTranscript` | `polishedJSON: String` (topic sections), `recording ←→` |
| `Summary` | `overview: String`, `actionItems: [String]`, `decisions: [String]`, `keyPoints: [String]`, `generatedAt: Date`, `recording ←→` |

Domain value types in `Core/Models` (`RecordingInfo`, `TranscriptSegmentModel`, `SentenceLabel`, `SummaryPayload`, `EnhancedTranscriptPayload`) are what services exchange. Views never touch Core Data or frameworks directly.

---

## 7. Folder structure

Mirrors NovelDex / FitnessApp. One clear module per concern.

```
Recaply/
├── App/                    RecaplyApp, RootView, MainTabView
├── Core/
│   ├── Data/               PersistenceController, Recaply.xcdatamodeld
│   ├── Models/             Domain value types + SentenceLabel enum
│   ├── Services/
│   │   ├── RecordingService, CameraService
│   │   ├── TranscriptionService
│   │   ├── ClassificationService, ActionItemClassifier
│   │   ├── SummarizationService, TranscriptEnhancementService
│   │   ├── LLMClient (GLM), DeepseekClient
│   │   └── KeychainStore
│   ├── Extensions/         Color+Theme (tokens), Date+, TimeInterval+
│   └── UI/                 EmptyStateView, SkeletonLoader, ProcessingStageView, …
├── Features/
│   ├── Record/             RecordView, RecordViewModel
│   ├── Library/            LibraryView, LibraryViewModel
│   ├── Detail/             RecordingDetailView, RecordingDetailViewModel
│   └── Settings/           SettingsView, SettingsViewModel
├── Resources/              Info.plist, Assets.xcassets, Models/ActionItemClassifier.mlmodel
└── RecaplyTests/           5+ XCTest files
```

`gen_pbxproj.py` (reused from NovelDex) emits a valid Xcode-14 / objectVersion-56 `project.pbxproj` from this tree.

---

## 8. Multiple AI Agents (feeds the 40-point section)

Six agents, each with clear file ownership and constructor-injected services. Any change to a shared contract is recorded in `.agents/SHARED_STATE.md`.

| Agent | Role | Owns |
|---|---|---|
| **0 Architect** | Scaffold, design tokens, Core Data stack, `gen_pbxproj.py`, `Info.plist` | `App/*`, `Core/Extensions`, `Core/Data/PersistenceController`, `Recaply.xcdatamodeld`, `gen_pbxproj.py` |
| **1 Capture** | Mic + camera recording, waveform | `RecordingService`, `CameraService`, `Features/Record/*` |
| **2 Transcription** | On-device speech-to-text, segmentation, task restart | `TranscriptionService`, transcript value types |
| **3 CoreML** | Train + integrate the text classifier, stub fallback | `ClassificationService`, `ActionItemClassifier.*`, `Resources/Models` |
| **4 LLM** | Enhancement + summarization, prompts, JSON, Keychain, Settings | `SummarizationService`, `TranscriptEnhancementService`, `LLMClient`, `DeepseekClient`, `KeychainStore`, `Features/Settings/*` |
| **5 Storage + UI** | Core Data wiring, Library, Detail, Processing screen, playback | `Core/Data/Models/*`, `Features/Library/*`, `Features/Detail/*`, Processing screen, playback bar |

### Shared contracts (do not break silently)
- `Recording { id, createdAt, audioURL, videoURL?, duration, tag, status }`
- `TranscriptSegmentModel { index, text, timestamp, label, confidence }`
- `SummaryPayload { overview, actionItems, decisions, keyPoints }`
- `EnhancedTranscriptPayload { clean: [Segment], polished: [TopicSection] }`
- Services are singletons, constructor-injected (`.shared` default, overridable in tests).

### Documentation artifacts
- `docs/superpowers/specs/2026-06-27-recaply-design.md` (this file)
- `.agents/RULES.md` — toolchain locks, file ownership, conventions, Definition of Done
- `.agents/SHARED_STATE.md` — status board (TODO/IN PROGRESS/STABLE/BLOCKED) + shared contracts
- `.kiro/specs/recaply-ios/tasks.md` — ordered tickets grouped per agent
- Workflow note describing the loop: pick ticket → implement within owned files → update status → cross-agent review → STABLE

---

## 9. Differentiators (vs a generic summarizer)

These make Recaply clearly independent and stronger than a classmate's likely 2-stage "transcribe → summarize" app:

1. **4-stage pipeline** with transcript upscaling (Raw → Clean → Polished → Summary).
2. **Custom CoreML sentence classifier**, color-coded — a real, value-driving ML feature.
3. **Hybrid on-device + cloud**: transcription and classification never leave the device; only enhancement/summarization use the cloud. Strong report narrative.
4. **Interactive transcript** — tap a segment to seek audio.
5. **Topic-segmented polished notes** — structured meeting notes, not a text wall.
6. **Checkable action items + open-items strip** — real follow-through, not a dump.
7. **Cinematic UI + motion + haptics.**
8. **Multi-agent build documentation** built in from day one.

---

## 10. Error handling and edge cases

| Case | Behavior |
|---|---|
| CoreML model missing | Stub returns `discussion`/0; app runs, badges hidden |
| No / invalid API key | Friendly empty state in Settings; calls skipped; no crash |
| Long recording (>1 min) | Speech task-restart concatenation |
| Network failure | Retry once, then fall back provider, then per-stage degrade |
| LLM JSON parse failure | Per-stage fallback (raw text); logged, surfaced as notice |
| Empty transcript | Show empty state, skip downstream stages |
| Camera/mic permission denied | Clear prompt with a link to Settings; record button disabled |

Never force-unwrap. All framework access is behind services.

---

## 11. Testing plan (XCTest)

Five or more targets, services injected for mocking:

1. `TranscriptSegmenterTests` — splitting and timestamp logic.
2. `ClassificationServiceTests` — stub model returns `discussion`; real model returns plausible labels.
3. `PromptBuilderTests` — enhancement and summary prompt construction; JSON decoding for both shapes (incl. topic sections and malformed input).
4. `RecordViewModelTests` — capture state machine (`idle → recording → stopping`).
5. `EnhancementParsingTests` — clean/polished/topic decode and fallback.

---

## 12. Out of scope (stretch, only after v1 demos)

- Insights dashboard with **Charts** (action items/decisions per week, total duration).
- Search across recordings.
- Export summary to Markdown / share sheet.
- Screen recording (Broadcast Extension), speaker diarization, cloud sync.

---

## 13. Risks

| Risk | Mitigation |
|---|---|
| First lab build fails (authored on Linux) | Compile verification is the **first** lab task, before any polish |
| Speech 1-min task limit | Task-restart logic; usage strings in `Info.plist` |
| CoreML model not ready | Stub fallback classifier ships by default |
| Duplicate-topic with a classmate | Differentiation (section 9) + independent implementation |

---

## 14. Definition of Done (v1)

- Builds and runs on Xcode 14.3.1 / iOS 16.4 simulator or device.
- Record (mic, optional camera) → Stop → Processing → Detail end-to-end.
- 4-stage pipeline visible; Clean/Polished/Raw transcript modes work; tap-to-seek works.
- Summary with color-coded, checkable action items and decisions.
- API key configured in Settings; graceful when missing.
- 5+ XCTest files pass.
- `.agents/` and `.kiro/specs/` documentation matches what was built.
