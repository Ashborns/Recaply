import SwiftUI

struct ProcessingStageView: View {
    @ObservedObject var coordinator: PipelineCoordinator
    let recording: RecordingInfo
    let onComplete: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 8) {
                Text("Recaply AI")
                    .font(.largeTitle.bold())
                    .foregroundColor(.textPrimary)
                Text(recording.title ?? recording.tag.rawValue.capitalized)
                    .font(.headline)
                    .foregroundColor(.textSecondary)
                Text("Turning your recording into clean notes")
                    .font(.subheadline)
                    .foregroundColor(.textTertiary)
            }

            VStack(spacing: 14) {
                ForEach(PipelineCoordinator.Stage.allCases, id: \.self) { stage in
                    row(for: stage)
                }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.glassStroke, lineWidth: 1)
            )

            if let error = coordinator.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.catAction)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(24)
        .background(Color.appBackground.ignoresSafeArea())
        .task { await coordinator.run(recording) }
        .onChange(of: coordinator.activeStage) { _ in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .onChange(of: coordinator.resultRecordingID) { id in
            guard let id else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete(id)
        }
    }

    private func row(for stage: PipelineCoordinator.Stage) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(indicatorFill(for: stage))
                    .frame(width: 34, height: 34)
                    .shadow(color: indicatorGlow(for: stage), radius: 10)
                indicatorIcon(for: stage)
            }
            Text(stage.title)
                .font(.headline)
                .foregroundColor(.textPrimary)
            Spacer()
        }
        .padding(14)
        .background(Color.glassFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(reduceMotion ? nil : .recaplySpring, value: coordinator.activeStage)
        .animation(reduceMotion ? nil : .recaplySpring, value: coordinator.completed)
    }

    private func indicatorIcon(for stage: PipelineCoordinator.Stage) -> some View {
        if coordinator.completed.contains(stage) {
            return AnyView(Image(systemName: "checkmark").font(.headline).foregroundColor(.textPrimary))
        }
        if coordinator.activeStage == stage {
            return AnyView(ProgressView().tint(.textPrimary))
        }
        return AnyView(Circle().fill(Color.textTertiary).frame(width: 8, height: 8))
    }

    private func indicatorFill(for stage: PipelineCoordinator.Stage) -> AnyShapeStyle {
        if coordinator.completed.contains(stage) { return AnyShapeStyle(Color.catDecision) }
        if coordinator.activeStage == stage { return AnyShapeStyle(Color.accentGradient) }
        return AnyShapeStyle(Color.glassStroke)
    }

    private func indicatorGlow(for stage: PipelineCoordinator.Stage) -> Color {
        coordinator.activeStage == stage ? .accentPurple.opacity(0.45) : .clear
    }
}
