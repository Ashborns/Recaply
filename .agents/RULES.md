# RULES — Recaply iOS Multi-Agent Build

Aturan global untuk semua agent yang berkontribusi ke Recaply. Baca ini sebelum
menulis kode apa pun. Spesifikasi resmi: `docs/superpowers/specs/2026-06-27-recaply-design.md`.

## 1. Lingkungan & Toolchain (LOCK)
- Dikembangkan di Linux/WSL **tanpa Mac**. Kode TIDAK bisa di-compile/test saat ditulis;
  verifikasi build = kegiatan lab. Project file di-generate lewat `python3 gen_pbxproj.py`.
- Target LOCK: **iOS 16.4, Swift 5.0, Xcode 14.3.1, objectVersion 56**.
- **DILARANG** pakai API iOS 17+. Khususnya:
  - **Tidak boleh `@Observable` macro** — gunakan `ObservableObject` + `@Published`.
  - Tidak boleh Apple Translation framework, tidak boleh `#Predicate` macro SwiftData.
- Framework sistem saja (AVFoundation, Speech, CoreML, CoreData, SwiftUI, NaturalLanguage).
  **Tidak ada SPM, tidak ada Firebase** — `project.pbxproj` nol package reference.
- Jangan pernah force-unwrap (`!` pada optional yang bisa nil). Semua akses framework
  dibungkus service, semua error ditangani (lihat design spec seksi 10).

## 2. Kepemilikan File
- Tiap agent hanya mengubah file dalam domainnya (lihat tabel di `SHARED_STATE.md`).
- Mengubah **kontrak bersama** wajib dicatat di `SHARED_STATE.md` dan tidak boleh
  memecah konsumen lain. Kontrak bersama: `RecordingInfo`, `TranscriptSegmentModel`,
  `SummaryPayload`, `EnhancedTranscriptPayload`, `SentenceLabel`, `SessionTag`,
  `PipelineStatus`, `PersistenceController`, dan protokol service.
- `project.pbxproj` dihasilkan oleh `gen_pbxproj.py` — **jangan edit manual**. Tambah
  file baru = jalankan ulang generator, lalu commit hasilnya.

## 3. Konvensi Kode
- Arsitektur **MVVM**: View → ViewModel (`@MainActor final class …: ObservableObject`)
  → Service. View **tidak boleh** menyentuh Core Data atau framework sistem langsung.
- Service adalah **singleton dengan constructor injection** (`.shared` default, bisa
  di-override di test) agar testable. Contoh:
  `init(client: LLMClient = .shared)`.
- Status pipeline memakai enum `PipelineStatus` (`captured → transcribing →
  classifying → enhancing → summarizing → ready / failed`).
- Tema: pakai token dari `Core/Extensions/Color+Theme.swift` (`Color.catAction`,
  `.accentPurple`, `Color.appBackground`, `recaplySpring`, dll). **Jangan hardcode
  warna/angka.** Hormati `@Environment(\.accessibilityReduceMotion)`.

## 4. Privasi & Keamanan
- Usage string wajib ada di `Info.plist` (mic, camera, speech) — sudah diset di Tahap 0.
- API key (GLM/Deepseek) disimpan di **Keychain** (`KeychainStore`), divalidasi saat
  disimpan, **jangan pernah commit credential asli**.
- Tidak ada `UIBackgroundModes` di v1 (foreground only).

## 5. Chunked Write Protocol
- Maksimum **~300–350 baris per operasi tulis**. File besar ditulis bertahap (append),
  bukan satu blok raksasa.
- Edit file existing pakai edit bedah (Edit tool), bukan rewrite penuh.

## 6. Definition of Done (per komponen)
- Kode konsisten dengan design spec & pola rujukan (NovelDex / FitnessApp).
- **Tidak ada referensi simbol yang belum didefinisikan** (cross-check import & tipe).
- Ditandai ✅ STABLE di `SHARED_STATE.md` **hanya setelah review silang** antar-agent.
- Verifikasi build akhir (Xcode 14.3.1 / iOS 16.4 simulator) dilakukan di lab —
  tanggung jawab bersama, **tugas pertama** sebelum polish apa pun.
