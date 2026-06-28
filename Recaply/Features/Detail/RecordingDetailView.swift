import SwiftUI

struct RecordingDetailView: View {
    @StateObject private var vm: RecordingDetailViewModel
    @StateObject private var playback = PlaybackController()
    @StateObject private var retryPipeline = PipelineCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var renameTitle = ""
    @State private var showRename = false
    @State private var showDelete = false
    @State private var showAskAI = false
    @State private var retryRecording: RecordingInfo?
    @Namespace private var transcriptModeNamespace

    init(recordingID: UUID) {
        _vm = StateObject(wrappedValue: RecordingDetailViewModel(recordingID: recordingID))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBar
                    header
                    insightStrip
                    audioPlaybackCard
                    if vm.recording?.status == .failed {
                        failedRecapCard
                    }
                    summaryCard
                    transcriptPicker
                    transcriptBody
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            playback.load(url: vm.recording?.audioURL)
            renameTitle = vm.recording?.title ?? ""
        }
        .sheet(isPresented: $showAskAI) {
            askAISheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appBackground)
        }
        .fullScreenCover(item: $retryRecording) { recording in
            ProcessingStageView(coordinator: retryPipeline, recording: recording) { _ in
                retryRecording = nil
                vm.reload()
            } onCancel: {
                retryRecording = nil
                vm.reload()
            }
            .task {
                await retryPipeline.run(recording)
            }
        }
        .alert("Rename session", isPresented: $showRename) {
            TextField("Session title", text: $renameTitle)
            Button("Save") { vm.rename(to: renameTitle) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this recording a title that is easy to find in Library.")
        }
        .confirmationDialog("Delete recording?", isPresented: $showDelete) {
            Button("Delete Recording", role: .destructive) {
                vm.deleteRecording()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the transcript, summary, and saved media files.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Color.surfaceRaised.opacity(0.92), in: Circle())
            }

            Spacer()

            Button {
                showAskAI = true
            } label: {
                Label("Ask AI", systemImage: "sparkles")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentPurple.opacity(0.18), in: Capsule())

            Button {
                renameTitle = vm.recording?.title ?? ""
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surfaceRaised.opacity(0.92), in: Capsule())

            exportMenu

            Button {
                showDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .foregroundColor(.catAction)
                    .frame(width: 38, height: 38)
                    .background(Color.catAction.opacity(0.10), in: Circle())
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            if let textURL = vm.exportTextURL {
                ShareLink(item: textURL) {
                    Label("Export Text", systemImage: "doc.text")
                }
            }
            if let jsonURL = vm.exportJSONURL {
                ShareLink(item: jsonURL) {
                    Label("Export JSON", systemImage: "curlybraces")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.headline)
                .foregroundColor(.textPrimary)
                .frame(width: 38, height: 38)
                .background(Color.surfaceRaised.opacity(0.92), in: Circle())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.recording?.title ?? "Untitled session")
                .font(.largeTitle.bold())
                .foregroundColor(.textPrimary)
            HStack(spacing: 10) {
                Text(vm.recording?.tag.rawValue.capitalized ?? "Session")
                Text(vm.recording?.duration.asClock ?? "00:00")
                Text("\(vm.segments.count) segments")
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.textTertiary)
        }
    }

    private var summaryCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: vm.summary == nil ? "exclamationmark.triangle.fill" : "sparkles")
                        .foregroundColor(vm.summary == nil ? .catAction : .accentCyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.summary == nil ? "Summary unavailable" : "AI Summary")
                            .font(.title3.bold())
                            .foregroundColor(.textPrimary)
                        Text(vm.summary == nil ? "Retry recap to generate a summary with GLM or Groq." : "Generated from the transcript using the AI agent.")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Text(vm.summary == nil ? "Failed" : "AI")
                        .font(.caption.bold())
                        .foregroundColor(vm.summary == nil ? .catAction : .accentCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                section("Overview", color: .accentCyan) {
                    Text(vm.overviewText)
                        .foregroundColor(.textSecondary)
                }
                section("Action items", color: .catAction) {
                    if vm.actionItems.isEmpty {
                        Text("No action items detected yet.").foregroundColor(.textTertiary)
                    } else {
                        ForEach(Array(vm.actionItems.enumerated()), id: \.offset) { index, item in
                            Button { vm.toggleActionItem(at: index) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: vm.checkedActionItems.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(.catAction)
                                    Text(item)
                                        .foregroundColor(.textPrimary)
                                        .strikethrough(vm.checkedActionItems.contains(index))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                section("Decisions", color: .catDecision) {
                    bulletList(vm.decisions)
                }
                section("Key points", color: .catQuestion) {
                    bulletList(vm.keyPoints)
                }
            }
        }
    }

    private var failedRecapCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.catAction)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI recap failed")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("The recording is saved, but the AI agents could not generate a recap.")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }

                Text("Try again when your connection/API keys are available. Recaply will use Groq first, then GLM / Z.ai. No local fallback recap will be generated.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)

                Button {
                    guard let recording = vm.recording else { return }
                    retryRecording = recording
                } label: {
                    Label("Retry Recap", systemImage: "arrow.clockwise")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentGradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var insightStrip: some View {
        HStack(spacing: 10) {
            insight("Actions", vm.labelCounts[.actionItem, default: 0], .catAction)
            insight("Decisions", vm.labelCounts[.decision, default: 0], .catDecision)
            insight("Questions", vm.labelCounts[.question, default: 0], .catQuestion)
            insight("Confidence", Int(vm.averageConfidence * 100), .accentCyan, suffix: "%")
        }
    }

    private func insight(_ title: String, _ value: Int, _ color: Color, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)\(suffix)")
                .font(.headline.monospacedDigit())
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var transcriptPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcript Views")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(transcriptModeCaption)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            HStack(spacing: 6) {
                ForEach(RecordingDetailViewModel.TranscriptMode.allCases) { mode in
                    transcriptModeButton(mode)
                }
            }
            .padding(4)
            .background(Color.surfaceRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
        }
    }

    private var askAISheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        askAIHeader
                        askAIComposer
                        askAIStatus
                        askAIAnswer
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showAskAI = false }
                        .foregroundColor(.accentCyan)
                }
            }
        }
    }

    private var askAIHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.accentGradient, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask AI")
                        .font(.largeTitle.bold())
                        .foregroundColor(.textPrimary)
                    Text(vm.recording?.title ?? "This recording")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
            }
            Text("Ask questions about the transcript, recap, decisions, or action items. Answers are limited to this recording's content.")
                .font(.footnote)
                .foregroundColor(.textTertiary)
        }
    }

    private var askAIComposer: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Question")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                TextEditor(text: $vm.askQuestionText)
                    .font(.body)
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96, maxHeight: 150)
                    .padding(10)
                    .background(Color.surfaceDeep.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if vm.askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Example: What were the main decisions in this meeting?")
                                .font(.body)
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        suggestedQuestionButton("What are the key points?")
                        suggestedQuestionButton("What action items were mentioned?")
                        suggestedQuestionButton("What decisions were made?")
                        suggestedQuestionButton("Explain this recording briefly.")
                    }
                }

                Button {
                    Task { await vm.askAI() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        if vm.isAskingAI {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(vm.isAskingAI ? "Thinking…" : "Ask")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canAskAI ? AnyShapeStyle(Color.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canAskAI)
            }
        }
    }

    @ViewBuilder
    private var askAIStatus: some View {
        if let warning = vm.askWarningText {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.catQuestion)
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.catQuestion.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if let error = vm.askErrorText {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(.catAction)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.catAction.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var askAIAnswer: some View {
        if let answer = vm.askAnswerText {
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(.accentCyan)
                        Text("Answer")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                    Text(answer)
                        .foregroundColor(.textSecondary)
                        .textSelection(.enabled)
                }
            }
        } else if !vm.isAskingAI {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggestions")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("Use Ask AI to clarify concepts, find decisions, list follow-ups, or turn the recording into a short explanation.")
                    .font(.footnote)
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var canAskAI: Bool {
        !vm.isAskingAI && !vm.askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func suggestedQuestionButton(_ question: String) -> some View {
        Button {
            vm.useSuggestedQuestion(question)
        } label: {
            Text(question)
                .font(.caption.bold())
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var transcriptModeCaption: String {
        switch vm.mode {
        case .clean: return "Readable transcript"
        case .polished: return "Presentation notes"
        case .raw: return "Original labels"
        }
    }

    private func transcriptModeButton(_ mode: RecordingDetailViewModel.TranscriptMode) -> some View {
        let isSelected = vm.mode == mode
        return Button {
            vm.mode = mode
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.caption.weight(.bold))
                Text(mode.rawValue)
                    .font(.caption.weight(isSelected ? .bold : .semibold))
            }
            .foregroundColor(isSelected ? .textPrimary : .textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentGradient)
                        .matchedGeometryEffect(id: "transcriptMode", in: transcriptModeNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var transcriptBody: some View {
        switch vm.mode {
        case .clean:
            VStack(spacing: 10) {
                ForEach(vm.cleanSegments, id: \.index) { clean in
                    segmentRow(index: clean.index, text: clean.text, timestamp: timestamp(for: clean.index))
                }
            }
        case .raw:
            VStack(spacing: 10) {
                ForEach(vm.segments) { segment in
                    segmentRow(index: segment.index, text: segment.text, timestamp: segment.timestamp, label: segment.label)
                }
            }
        case .polished:
            VStack(spacing: 12) {
                ForEach(vm.polishedSections, id: \.heading) { section in
                    glassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.heading)
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            Text(section.body)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var audioPlaybackCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentCyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recording audio")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("Play the original recording or jump from transcript timestamps.")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Text(playback.duration.asClock)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }

                HStack(spacing: 12) {
                    Button { playback.toggle() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.accentGradient, in: Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 6) {
                        Slider(value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }), in: 0...max(playback.duration, 1))
                            .tint(.accentPurple)
                        HStack {
                            Text(playback.currentTime.asClock)
                            Spacer()
                            Text(max(0, playback.duration - playback.currentTime).asClock + " left")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.textTertiary)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.headline).foregroundColor(.textPrimary)
            }
            content()
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text("None yet.").foregroundColor(.textTertiary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)").foregroundColor(.textSecondary)
                }
            }
        }
    }

    private func segmentRow(index: Int, text: String, timestamp: TimeInterval, label: SentenceLabel = .discussion) -> some View {
        Button {
            playback.seek(to: timestamp)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(color(for: label)).frame(width: 9, height: 9).padding(.top, 6)
                Text(timestamp.asClock)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.textTertiary)
                    .frame(width: 52, alignment: .leading)
                Text(text).foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(12)
            .background(Color.glassFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func timestamp(for index: Int) -> TimeInterval {
        vm.segments.first(where: { $0.index == index })?.timestamp ?? 0
    }

    private func color(for label: SentenceLabel) -> Color {
        switch label {
        case .actionItem: return .catAction
        case .decision: return .catDecision
        case .question: return .catQuestion
        case .discussion: return .catDiscussion
        }
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }
}
