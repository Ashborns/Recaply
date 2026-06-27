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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                header

                Spacer()

                TagSegmentedControl(selection: $vm.tag) {
                    haptic(.light)
                }
                .padding(.horizontal, 20)
                .disabled(vm.phase != .idle)
                .opacity(vm.phase != .idle ? 0.6 : 1)

                nameField
                    .padding(.horizontal, 20)
                    .disabled(vm.phase != .idle)
                    .opacity(vm.phase != .idle ? 0.6 : 1)

                Spacer()

                WaveformView(level: vm.level, isActive: vm.phase == .recording)
                    .frame(height: 96)
                    .padding(.horizontal, 20)

                Spacer()

                if let message = vm.startError {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.catAction)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }

                RecordButton(phase: vm.phase, action: onTapRecord)
                    .accessibilityLabel(vm.phase == .recording ? "Stop recording" : "Start recording")

                cameraRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            .padding(.vertical, 24)

            if showSaved {
                SavedBanner()
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                    )
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(reduceMotion ? nil : .recaplySpring, value: vm.phase)
        .animation(reduceMotion ? nil : .recaplySpring, value: showSaved)
        .animation(reduceMotion ? nil : .recaplySpring, value: vm.startError)
        .onChange(of: vm.lastRecording) { recording in
            guard let recording else { return }
            onCaptureSaved(recording)
        }
        .fullScreenCover(item: $processingRecording) { recording in
            ProcessingStageView(coordinator: pipeline, recording: recording) { _ in
                processingRecording = nil
                showSaved = false
                vm.acknowledgeCapture()
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

    private var header: some View {
        VStack(spacing: 6) {
            Text("Record")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(vm.phase == .recording ? "Listening…" : "Capture a meeting or lecture")
                .font(.subheadline)
                .foregroundColor(.textTertiary)
                .monospacedDigit()
        }
        .padding(.top, 8)
    }

    private var nameField: some View {
        TextField("Name this session", text: $vm.title)
            .textInputAutocapitalization(.words)
            .font(.body)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.glassFill)
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
            Text("Camera")
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
                .fill(.ultraThinMaterial)
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
                    Text(tag.rawValue.capitalized)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
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
                .fill(.ultraThinMaterial)
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
            Circle()
                .fill(
                    isRecording
                        ? AnyShapeStyle(Color.catAction)
                        : AnyShapeStyle(Color.accentGradient)
                )
                .frame(width: 88, height: 88)
                .overlay(
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(
                    color: (isRecording ? Color.catAction : Color.accentPurple).opacity(0.45),
                    radius: 22
                )
        }
        .buttonStyle(.plain)
        .disabled(phase == .stopping)
        .animation(reduceMotion ? nil : .recaplySpring, value: phase)
    }
}

// MARK: - Saved confirmation banner

private struct SavedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.catDecision)
            Text("Recording saved")
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
