import SwiftUI

struct RecordingDetailView: View {
    @StateObject private var vm: RecordingDetailViewModel
    @StateObject private var playback = PlaybackController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(recordingID: UUID) {
        _vm = StateObject(wrappedValue: RecordingDetailViewModel(recordingID: recordingID))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summaryCard
                    transcriptPicker
                    transcriptBody
                        .padding(.bottom, 92)
                }
                .padding(20)
            }
            playbackBar
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { playback.load(url: vm.recording?.audioURL) }
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
                section("Overview", color: .accentCyan) {
                    Text(vm.summary?.overview ?? "Summary will appear after processing. Transcript remains available below.")
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
                    bulletList(vm.summary?.decisions ?? [])
                }
                section("Key points", color: .catQuestion) {
                    bulletList(vm.summary?.keyPoints ?? [])
                }
            }
        }
    }

    private var transcriptPicker: some View {
        Picker("Transcript", selection: $vm.mode) {
            ForEach(RecordingDetailViewModel.TranscriptMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
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

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.accentGradient, in: Circle())
            }
            Text(playback.currentTime.asClock)
                .font(.caption.monospacedDigit())
                .foregroundColor(.textSecondary)
            Slider(value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }), in: 0...max(playback.duration, 1))
                .tint(.accentPurple)
            Text(playback.duration.asClock)
                .font(.caption.monospacedDigit())
                .foregroundColor(.textTertiary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }
}
