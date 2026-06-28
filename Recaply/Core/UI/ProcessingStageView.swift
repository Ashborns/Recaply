import SwiftUI

struct ProcessingStageView: View {
    @ObservedObject var coordinator: PipelineCoordinator
    let recording: RecordingInfo
    let onComplete: (UUID) -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsedSeconds = 0
    @State private var pulse = false
    @State private var tipIndex = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var activeIndex: Int {
        guard let activeStage = coordinator.activeStage else { return coordinator.completed.count }
        return PipelineCoordinator.Stage.allCases.firstIndex(of: activeStage) ?? 0
    }

    private var progress: CGFloat {
        let total = CGFloat(PipelineCoordinator.Stage.allCases.count)
        return min(1, max(0.08, CGFloat(coordinator.completed.count) / total))
    }

    private var displayedProgress: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    hero
                    timeline
                    aiRouteCard
                    stageDetails
                    processingTip
                    insightCards
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
        }
        .onChange(of: coordinator.activeStage) { _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            tipIndex += 1
        }
        .onChange(of: coordinator.resultRecordingID) { id in
            guard let id else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete(id)
        }
        .onAppear {
            pulse = true
        }
        .onReceive(timer) { _ in
            guard coordinator.isRunning, coordinator.errorMessage == nil else { return }
            elapsedSeconds += 1
            if elapsedSeconds % 5 == 0 { tipIndex += 1 }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Preparing Recap")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(recording.title ?? recording.tag.rawValue.capitalized)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(displayedProgress)%")
                    .font(.caption.bold())
                    .foregroundColor(.accentCyan)
                Text(TimeInterval(elapsedSeconds).asClock)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.textTertiary)
            }
            Button("Run in Background") { onCancel() }
                .font(.caption.weight(.semibold))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.surfaceRaised, in: Capsule())
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentPurple.opacity(0.22))
                    .frame(width: 158, height: 158)
                    .blur(radius: 10)
                    .scaleEffect(pulse && coordinator.activeStage != nil ? 1.08 : 0.92)
                    .opacity(pulse && coordinator.activeStage != nil ? 0.85 : 0.45)
                Circle()
                    .stroke(Color.accentGradient, lineWidth: 12)
                    .frame(width: 118, height: 118)
                    .rotationEffect(.degrees(pulse && coordinator.activeStage != nil ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 2.8).repeatForever(autoreverses: false), value: pulse)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentCyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 138, height: 138)
                    .rotationEffect(.degrees(-90))
                Image(systemName: statusIconName)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(statusIconColor)
                    .scaleEffect(pulse && coordinator.activeStage != nil ? 1.04 : 0.96)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            }

            VStack(spacing: 6) {
                Text(currentTitle)
                    .font(.title3.bold())
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                Text(currentSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            progressBar
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.accentPurple.opacity(0.20), .surfaceRaised.opacity(0.92)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
        .shadow(color: Color.accentPurple.opacity(0.18), radius: 28, x: 0, y: 16)
        .animation(reduceMotion ? nil : .recaplySpring, value: coordinator.activeStage)
        .animation(reduceMotion ? nil : .recaplySpring, value: coordinator.errorMessage)
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color.accentGradient)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 10)
            HStack {
                Text("Stage \(min(activeIndex + 1, PipelineCoordinator.Stage.allCases.count)) of \(PipelineCoordinator.Stage.allCases.count)")
                Spacer()
                Text("\(displayedProgress)% complete")
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.textTertiary)
        }
    }

    private var timeline: some View {
        HStack(spacing: 8) {
            ForEach(Array(PipelineCoordinator.Stage.allCases.enumerated()), id: \.element) { index, stage in
                stageDot(stage, index: index)
                if index < PipelineCoordinator.Stage.allCases.count - 1 {
                    Rectangle()
                        .fill(index < coordinator.completed.count ? AnyShapeStyle(Color.accentGradient) : AnyShapeStyle(Color.white.opacity(0.10)))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func stageDot(_ stage: PipelineCoordinator.Stage, index: Int) -> some View {
        let isDone = coordinator.completed.contains(stage)
        let isActive = coordinator.activeStage == stage
        return ZStack {
            Circle()
                .fill(isDone || isActive ? AnyShapeStyle(Color.accentGradient) : AnyShapeStyle(Color.surfaceRaised))
                .frame(width: 34, height: 34)
            Image(systemName: isDone ? "checkmark" : "\(index + 1).circle.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(isDone || isActive ? .white : .textTertiary)
        }
    }

    private var stageDetails: some View {
        VStack(spacing: 10) {
            ForEach(PipelineCoordinator.Stage.allCases, id: \.self) { stage in
                stageDetailRow(stage)
            }
        }
    }

    private var aiRouteCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: aiRouteIcon)
                .font(.headline)
                .foregroundColor(aiRouteColor)
                .frame(width: 38, height: 38)
                .background(aiRouteColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(aiRouteTitle)
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                Text(aiRouteDescription)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }

    private func stageDetailRow(_ stage: PipelineCoordinator.Stage) -> some View {
        let isDone = coordinator.completed.contains(stage)
        let isActive = coordinator.activeStage == stage
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? AnyShapeStyle(Color.accentGradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                    .frame(width: 34, height: 34)
                if isActive {
                    ProgressView()
                        .tint(.accentCyan)
                } else {
                    Image(systemName: isDone ? "checkmark" : stageIcon(stage))
                        .font(.caption.bold())
                        .foregroundColor(isDone ? .white : .textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(.subheadline.bold())
                    .foregroundColor(isActive || isDone ? .textPrimary : .textTertiary)
                Text(stage.subtitle)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(isDone ? "Done" : (isActive ? "Working" : "Queued"))
                .font(.caption2.bold())
                .foregroundColor(isDone ? .catDecision : (isActive ? .accentCyan : .textTertiary))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .padding(12)
        .background(isActive ? Color.accentPurple.opacity(0.12) : Color.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isActive ? Color.accentCyan.opacity(0.35) : Color.glassStroke, lineWidth: 1))
    }

    private var processingTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.catQuestion)
            VStack(alignment: .leading, spacing: 3) {
                Text("What is happening now")
                    .font(.caption.bold())
                    .foregroundColor(.textPrimary)
                Text(currentTip)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.catQuestion.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.catQuestion.opacity(0.22), lineWidth: 1))
    }

    private var insightCards: some View {
        VStack(spacing: 12) {
            if let error = coordinator.errorMessage {
                errorCard(error)
            } else if let warning = coordinator.warningMessage {
                warningCard(warning)
            } else {
                miniCard(icon: "quote.bubble.fill", title: "Clean Transcript", body: "Filler words are removed while the original audio stays saved.")
                miniCard(icon: "checklist.checked", title: "Action Items", body: "Tasks, questions, and decisions are extracted automatically.")
                miniCard(icon: "doc.text.magnifyingglass", title: "Presentation Ready", body: "The final screen opens with recap, labels, and polished notes.")
            }
        }
    }

    private func miniCard(icon: String, title: String, body: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(.accentCyan)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                Text(body)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surfaceRaised.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.catAction)
                Text("Audio saved, recap needs attention")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
            }
            Text(error)
                .font(.footnote)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Retry Recap") {
                    Task { await coordinator.run(recording) }
                }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.accentGradient, in: Capsule())
                Button("Open Recording") { onComplete(recording.id) }
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.06), in: Capsule())
                Button("Back") { onCancel() }
                    .font(.subheadline.bold())
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }

    private func warningCard(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.catQuestion)
                Text("AI fallback used")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
            }
            Text(warning)
                .font(.footnote)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your recap is still saved, but please review it because a backup AI/local fallback generated part of it.")
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.catQuestion.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.catQuestion.opacity(0.35), lineWidth: 1))
    }

    private var currentTitle: String {
        if coordinator.errorMessage != nil { return "We could not finish the recap" }
        if coordinator.warningMessage != nil { return "Recap ready with fallback" }
        return coordinator.activeStage?.title ?? "Finalizing your notes"
    }

    private var currentSubtitle: String {
        if coordinator.errorMessage != nil {
            return "Your audio is still saved. You can open the recording or try again with clearer speech."
        }
        if coordinator.warningMessage != nil {
            return "The main AI/server had an issue, so Recaply used a fallback and kept your recap available."
        }
        return coordinator.activeStage?.subtitle ?? "Almost done."
    }

    private var currentTip: String {
        let tips: [String]
        switch coordinator.activeStage {
        case .transcribing:
            tips = [
                "Recaply is turning the recording into timestamped text.",
                "Live captions may be used as a backup if final transcription has an issue.",
                "Clearer audio usually produces better summaries and cleaner action items."
            ]
        case .classifying:
            tips = [
                "Each transcript segment is being labeled as discussion, question, decision, or action item.",
                "These labels help the recap separate follow-ups from general notes.",
                "Classification runs locally, so this stage can continue even when AI fallback is needed."
            ]
        case .enhancing:
            tips = [
                "The transcript is being cleaned while preserving the original meaning.",
                "Recaply is removing filler and grouping the discussion into readable sections.",
                "If the main AI fails, Groq or local fallback will keep the recap usable."
            ]
        case .summarizing:
            tips = [
                "Recaply is extracting overview, key points, decisions, and action items.",
                "The summary is constrained to what was actually said in the recording.",
                "After this, you can ask follow-up questions from the recording detail page."
            ]
        case nil:
            tips = ["Final checks are running before opening your recap."]
        }
        return tips[abs(tipIndex) % tips.count]
    }

    private func stageIcon(_ stage: PipelineCoordinator.Stage) -> String {
        switch stage {
        case .transcribing: return "waveform"
        case .classifying: return "tag.fill"
        case .enhancing: return "wand.and.stars"
        case .summarizing: return "doc.text.magnifyingglass"
        }
    }

    private var aiRouteTitle: String {
        if coordinator.errorMessage != nil { return "Processing issue detected" }
        if coordinator.warningMessage != nil { return "Fallback route used" }
        if coordinator.activeStage == .enhancing || coordinator.activeStage == .summarizing {
            return "Primary AI route"
        }
        return "Local processing first"
    }

    private var aiRouteDescription: String {
        if coordinator.errorMessage != nil {
            return "Recaply could not finish the current stage. Your audio is still saved."
        }
        if let warning = coordinator.warningMessage {
            return warning
        }
        if coordinator.activeStage == .enhancing || coordinator.activeStage == .summarizing {
            return "Recaply is trying Groq first. If it fails, GLM / Z.ai is used next. No local fallback recap will be generated."
        }
        return "Transcription and classification prepare the recording before AI enhancement starts."
    }

    private var aiRouteIcon: String {
        if coordinator.errorMessage != nil { return "xmark.octagon.fill" }
        if coordinator.warningMessage != nil { return "arrow.triangle.2.circlepath.circle.fill" }
        if coordinator.activeStage == .enhancing || coordinator.activeStage == .summarizing { return "sparkles" }
        return "cpu.fill"
    }

    private var aiRouteColor: Color {
        if coordinator.errorMessage != nil { return .catAction }
        if coordinator.warningMessage != nil { return .catQuestion }
        if coordinator.activeStage == .enhancing || coordinator.activeStage == .summarizing { return .accentCyan }
        return .textTertiary
    }

    private var statusIconName: String {
        if coordinator.errorMessage != nil { return "waveform.badge.exclamationmark" }
        if coordinator.warningMessage != nil { return "exclamationmark.triangle.fill" }
        return "sparkles"
    }

    private var statusIconColor: Color {
        if coordinator.errorMessage != nil { return .catAction }
        if coordinator.warningMessage != nil { return .catQuestion }
        return .accentCyan
    }
}
