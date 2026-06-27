import SwiftUI
import UIKit

/// Cinematic capture screen: tag + name, live waveform, record/stop, optional camera.
///
/// Bound to `RecordViewModel`. On stop it shows a brief "Recording saved" confirmation
/// and returns the button to idle via `vm.acknowledgeCapture()`. The Phase 5 pipeline
/// and Processing screen attach at the marked hook instead of this placeholder.
struct RecordView: View {
    @StateObject private var vm = RecordViewModel()
    @StateObject private var pipeline = PipelineCoordinator()
    @State private var showSaved = false
    @State private var processingRecording: RecordingInfo?
    @State private var detailRoute: DetailRoute?
    @State private var processingBanner: String?
    @State private var liveNotesAutoFollow = true
    @State private var liveNotesScrollTrigger = 0
    @State private var liveNotesResumeTask: Task<Void, Never>?
    @State private var liveNotesFollowTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    heroCard
                    sessionCard
                    waveformCard
                    liveTranscriptCard

                    if let message = vm.startError {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.catAction)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                    }

                    RecordButton(phase: vm.phase, action: onTapRecord)
                        .padding(.top, 4)
                        .accessibilityLabel(vm.phase == .recording ? "Stop recording" : "Start recording")

                    cameraRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 138)
            }

            if showSaved {
                FloatingBanner(icon: "checkmark.circle.fill", text: "Recording saved", color: .catDecision)
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                    )
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            if let processingBanner {
                FloatingBanner(icon: "sparkles", text: processingBanner, color: .accentCyan)
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                    )
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(reduceMotion ? nil : .recaplySpring, value: vm.phase)
        .animation(reduceMotion ? nil : .recaplySpring, value: showSaved)
        .animation(reduceMotion ? nil : .recaplySpring, value: processingBanner)
        .animation(reduceMotion ? nil : .recaplySpring, value: vm.startError)
        .onChange(of: vm.lastRecording) { recording in
            guard let recording else { return }
            onCaptureSaved(recording)
        }
        .onChange(of: vm.phase) { phase in
            if phase == .recording {
                startLiveNotesContinuousFollow()
            } else {
                stopLiveNotesContinuousFollow()
            }
        }
        .onChange(of: pipeline.resultRecordingID) { id in
            guard id != nil, processingRecording == nil else { return }
            processingBanner = pipeline.warningMessage == nil ? "Recap ready in Library" : "Recap ready, but AI fallback was used."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if processingBanner == "Recap ready in Library" || processingBanner == "Recap ready, but AI fallback was used." {
                    processingBanner = nil
                }
            }
        }
        .onChange(of: pipeline.warningMessage) { message in
            guard message != nil, pipeline.errorMessage == nil, processingRecording == nil else { return }
            processingBanner = "AI fallback used. Please review recap."
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        .onChange(of: pipeline.errorMessage) { message in
            guard message != nil, processingRecording == nil else { return }
            processingBanner = "Audio saved. Recap needs attention."
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        .fullScreenCover(item: $processingRecording) { recording in
            ProcessingStageView(coordinator: pipeline, recording: recording) { _ in
                processingRecording = nil
                showSaved = false
                processingBanner = nil
                vm.acknowledgeCapture()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    detailRoute = DetailRoute(id: recording.id)
                }
            } onCancel: {
                processingRecording = nil
                showSaved = false
                processingBanner = "Preparing recap in background"
                vm.acknowledgeCapture()
            }
        }
        .fullScreenCover(item: $detailRoute) { route in
            NavigationStack {
                RecordingDetailView(recordingID: route.id)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { detailRoute = nil }
                                .foregroundColor(.accentCyan)
                        }
                    }
            }
        }
        .onChange(of: vm.cameraOn) { turnedOn in
            guard turnedOn else { return }
            Task {
                let granted = await vm.enableCamera()
                if !granted {
                    vm.startError = "Camera access is required to record video."
                }
            }
        }
    }

    // MARK: - Pieces

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recaply")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(vm.phase == .recording ? "Recording live audio…" : "Capture meetings or lectures, then turn them into clean notes, action items, and decisions.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                statusPill
            }

            HStack(spacing: 12) {
                metric(title: "Timer", value: vm.elapsed.asClock, color: .accentCyan)
                metric(title: "Mode", value: vm.tag.rawValue.capitalized, color: .accentPurple)
            }

            pipelinePreview
        }
        .padding(20)
        .background(
            LinearGradient(colors: [.accentPurple.opacity(0.28), .accentCyan.opacity(0.10), .white.opacity(0.04)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
        .shadow(color: Color.accentPurple.opacity(0.18), radius: 24, x: 0, y: 14)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.phase == .recording ? Color.catAction : Color.catDecision)
                .frame(width: 8, height: 8)
            Text(vm.phase == .recording ? "Live" : "Ready")
                .font(.caption.bold())
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pipelinePreview: some View {
        HStack(spacing: 8) {
            pipelineStep("Transcript", "waveform")
            pipelineStep("Actions", "checkmark.circle.fill")
            pipelineStep("Notes", "sparkles")
            pipelineStep("Recap", "doc.text.fill")
        }
    }

    private func pipelineStep(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(.accentCyan)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sessionCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Session setup")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(vm.tag.shortDescription)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }

            TagSegmentedControl(selection: $vm.tag) {
                haptic(.light)
            }
            .disabled(vm.phase != .idle)
            .opacity(vm.phase != .idle ? 0.6 : 1)

            nameField
                .disabled(vm.phase != .idle)
                .opacity(vm.phase != .idle ? 0.6 : 1)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.surfaceRaised.opacity(0.86))
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }

    private var waveformCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(vm.phase == .recording ? "Listening…" : "Audio monitor")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(vm.phase == .recording ? vm.elapsed.asClock : "00:00")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.textTertiary)
            }
            WaveformView(level: vm.level, isActive: vm.phase == .recording)
                .frame(height: 96)
        }
        .padding(16)
        .background(Color.surfaceDeep.opacity(0.90), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }

    private var liveTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.accentCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Notes")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(vm.liveCaptionStatus)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                if vm.phase == .recording {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.catDecision)
                            .frame(width: 7, height: 7)
                        Text("Realtime")
                            .font(.caption2.bold())
                            .foregroundColor(.catDecision)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.catDecision.opacity(0.12), in: Capsule())
                }
            }

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(liveTranscriptText)
                            .font(.body)
                            .foregroundColor(vm.liveTranscript.isEmpty ? .textTertiary : .textPrimary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(14)
                        Color.clear
                            .frame(height: 1)
                            .id("live-notes-bottom")
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in pauseLiveNotesAutoFollow() }
                        .onEnded { _ in scheduleLiveNotesAutoResume() }
                )
                .onAppear {
                    scrollLiveNotesIfNeeded(proxy, force: true)
                }
                .onChange(of: liveTranscriptText) { _ in
                    scrollLiveNotesIfNeeded(proxy)
                }
                .onChange(of: liveNotesScrollTrigger) { _ in
                    scrollLiveNotesIfNeeded(proxy, force: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 176, alignment: .topLeading)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))

            HStack(spacing: 10) {
                metaPill("\(liveTranscriptWordCount) words", "text.word.spacing")
                metaPill(RecaplySpeechLanguage.selected.title, "globe.asia.australia.fill")
                Spacer()
                if vm.phase == .recording, vm.liveTranscript.count > liveTranscriptText.count {
                    Text("Showing latest")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textTertiary)
                } else if vm.phase == .recording, !liveNotesAutoFollow {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(16)
        .background(Color.surfaceRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
        .animation(reduceMotion ? nil : .recaplySpring, value: vm.liveTranscript)
    }

    private var liveTranscriptText: String {
        if !vm.liveTranscript.isEmpty { return truncatedLiveTranscript(vm.liveTranscript) }
        if vm.phase == .recording {
            return "Start speaking. Recaply will show a rough live transcript here while recording."
        }
        return "Your live transcript preview will appear here during recording."
    }

    private var liveTranscriptWordCount: Int {
        vm.liveTranscript
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private func truncatedLiveTranscript(_ text: String) -> String {
        let limit = 1_400
        guard text.count > limit else { return text }
        return "… " + String(text.suffix(limit))
    }

    private func metaPill(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(.textTertiary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func pauseLiveNotesAutoFollow() {
        guard vm.phase == .recording else { return }
        liveNotesAutoFollow = false
        scheduleLiveNotesAutoResume()
    }

    private func scheduleLiveNotesAutoResume() {
        liveNotesResumeTask?.cancel()
        liveNotesResumeTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                liveNotesAutoFollow = true
                liveNotesScrollTrigger += 1
            }
        }
    }

    private func startLiveNotesContinuousFollow() {
        liveNotesFollowTask?.cancel()
        liveNotesFollowTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard vm.phase == .recording, liveNotesAutoFollow, !vm.liveTranscript.isEmpty else { return }
                    liveNotesScrollTrigger += 1
                }
            }
        }
    }

    private func stopLiveNotesContinuousFollow() {
        liveNotesFollowTask?.cancel()
        liveNotesFollowTask = nil
    }

    private func scrollLiveNotesIfNeeded(_ proxy: ScrollViewProxy, force: Bool = false) {
        guard force || liveNotesAutoFollow else { return }
        guard !vm.liveTranscript.isEmpty else { return }
        let scrollAction = {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                proxy.scrollTo("live-notes-bottom", anchor: .bottom)
            }
        }

        DispatchQueue.main.async(execute: scrollAction)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard force || liveNotesAutoFollow else { return }
            scrollAction()
        }
    }

    private var nameField: some View {
        TextField("Add title, e.g. iOS final demo", text: $vm.title)
            .textInputAutocapitalization(.words)
            .font(.body)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.glassStroke, lineWidth: 1)
            )
    }

    private var cameraRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .foregroundColor(.textSecondary)
            Text("Attach video context")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Toggle("", isOn: $vm.cameraOn)
                .labelsHidden()
                .tint(.accentPurple)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surfaceRaised.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.glassStroke, lineWidth: 1)
        )
        // Lock the toggle to idle: flipping camera mid-recording would leak the
        // session / orphan the mp4 (stop while "on" but never started, or vice versa).
        .disabled(vm.phase != .idle)
        .opacity(vm.phase != .idle ? 0.6 : 1)
        .accessibilityLabel("Camera")
    }

    // MARK: - Actions

    private func onTapRecord() {
        switch vm.phase {
        case .idle:
            haptic(.medium)
            // `start` is async (camera config suspends off the main thread).
            Task {
                do {
                    try await vm.start(tag: vm.tag, title: vm.title)
                } catch {
                    vm.startError = friendlyStartError(error)
                }
            }
        case .recording:
            haptic(.medium)
            vm.stop()
            // MARK: - Phase 5 hook
            // When the pipeline lands, this is where the Processing screen is presented
            // and PipelineCoordinator.run(recording) kicks off (guarding lastRecording).
            // For Phase 1 we fall through to the saved-confirmation handler below.
        case .stopping:
            break
        }
    }

    /// Phase 5 handoff: persist and process the finished capture in the full-screen
    /// Processing view. Detail navigation is added by the Library/Detail phase.
    private func onCaptureSaved(_ recording: RecordingInfo) {
        withAnimation(reduceMotion ? nil : .recaplySpring) { showSaved = true }
        processingRecording = recording
        Task { await pipeline.run(recording) }
    }

    /// Distinguishes camera failures (authorization / configuration) from mic/engine
    /// failures so the inline message points at the right Settings pane.
    private func friendlyStartError(_ error: Error) -> String {
        switch error {
        case CameraError.notAuthorized:
            return "Camera access is required to record video."
        case CameraError.configurationFailed:
            return "Couldn't start the camera. Try again, or record audio only."
        default:
            // Mic session / engine / file write errors — surface the detail.
            return "Couldn't start recording. Check microphone access in Settings. (\(error.localizedDescription))"
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private struct DetailRoute: Identifiable {
    let id: UUID
}

// MARK: - Tag segmented control

/// Glass Meeting | Lecture picker with a sliding accent-gradient highlight.
private struct TagSegmentedControl: View {
    @Binding var selection: SessionTag
    let onChange: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SessionTag.allCases, id: \.self) { tag in
                let isSelected = selection == tag
                Button {
                    guard selection != tag else { return }
                    selection = tag
                    onChange()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tag.iconName)
                            .font(.caption.weight(.bold))
                        Text(tag.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(isSelected ? .textPrimary : .textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentGradient)
                                .matchedGeometryEffect(id: "tagHighlight", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.glassStroke, lineWidth: 1)
        )
        .animation(reduceMotion ? nil : .recaplySpring, value: selection)
    }
}

// MARK: - Waveform

/// Row of capsule bars whose heights follow the mic level, animated with recaplySpring.
private struct WaveformView: View {
    let level: Float
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barCount = 36
    /// Fixed per-bar envelope so the waveform breathes organically instead of rising
    /// as a single uniform block. `static` so it is built once, not recomputed at 20Hz.
    private static let envelope: [CGFloat] = {
        (0..<Self.barCount).map { i in
            let a = sin(Double(i) * 1.7) * 0.5 + 0.5
            let b = sin(Double(i) * 0.6 + 1.3) * 0.5 + 0.5
            return CGFloat(0.35 + 0.65 * (a + b) * 0.5)
        }
    }()

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: spacing(for: geo.size.width)) {
                ForEach(0..<Self.barCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(Color.accentGradient)
                        .frame(width: 4, height: barHeight(i))
                        .opacity(barOpacity(i))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .animation(reduceMotion ? nil : .recaplySpring, value: level)
        .animation(reduceMotion ? nil : .recaplySpring, value: isActive)
    }

    private func spacing(for width: CGFloat) -> CGFloat {
        max(3, (width - CGFloat(Self.barCount) * 4) / CGFloat(max(1, Self.barCount - 1)))
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let minH: CGFloat = 6
        let maxH: CGFloat = 88
        guard isActive else { return minH }
        let env = Self.envelope[i % Self.envelope.count]
        let lvl = CGFloat(max(0, min(1, level)))
        return minH + (maxH - minH) * lvl * env
    }

    /// Gentle edge falloff so the center of the waveform reads as the loudest.
    private func barOpacity(_ i: Int) -> Double {
        guard isActive else { return 0.35 }
        let center = Double(Self.barCount - 1) / 2
        let distance = abs(Double(i) - center) / (center + 1)
        return 0.5 + 0.5 * (1 - distance)
    }
}

// MARK: - Record button

/// Large record / stop affordance that changes color and icon by capture phase.
private struct RecordButton: View {
    let phase: RecordViewModel.Phase
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { phase == .recording }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(buttonFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: shadowColor, radius: 22, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(phase == .stopping)
        .animation(reduceMotion ? nil : .recaplySpring, value: phase)
    }

    private var iconName: String {
        switch phase {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .stopping: return "hourglass"
        }
    }

    private var title: String {
        switch phase {
        case .idle: return "Start Recording"
        case .recording: return "Stop & Generate Recap"
        case .stopping: return "Saving Audio"
        }
    }

    private var subtitle: String {
        switch phase {
        case .idle: return "One tap to capture and analyze"
        case .recording: return "Audio is being captured clearly"
        case .stopping: return "Preparing your AI recap"
        }
    }

    private var buttonFill: AnyShapeStyle {
        switch phase {
        case .idle: return AnyShapeStyle(Color.accentGradient)
        case .recording: return AnyShapeStyle(Color.catAction)
        case .stopping: return AnyShapeStyle(Color.surfaceRaised)
        }
    }

    private var shadowColor: Color {
        switch phase {
        case .idle: return Color.accentPurple.opacity(0.40)
        case .recording: return Color.catAction.opacity(0.35)
        case .stopping: return Color.black.opacity(0.25)
        }
    }
}

// MARK: - Saved confirmation banner

private struct FloatingBanner: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().stroke(Color.glassStroke, lineWidth: 1)
        )
    }
}
