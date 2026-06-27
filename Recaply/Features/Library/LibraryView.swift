import SwiftUI

struct LibraryView: View {
    @StateObject private var vm = LibraryViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Library")
                        .font(.largeTitle.bold())
                        .foregroundColor(.textPrimary)

                    if let latest = vm.latest {
                        NavigationLink(value: latest.id) { heroCard(latest) }
                            .buttonStyle(.plain)
                        ForEach(vm.older) { recording in
                            NavigationLink(value: recording.id) { row(recording) }
                                .buttonStyle(.plain)
                        }
                    } else {
                        EmptyStateView(title: "No recordings yet", message: "Record a meeting or lecture to see AI notes here.")
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationDestination(for: UUID.self) { id in
                RecordingDetailView(recordingID: id)
            }
            .onAppear { vm.reload() }
        }
    }

    private func heroCard(_ recording: RecordingInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LATEST · \(recording.tag.rawValue.uppercased())")
                .font(.caption.bold())
                .foregroundColor(.accentCyan)
            Text(recording.title ?? "Untitled session")
                .font(.title3.bold())
                .foregroundColor(.textPrimary)
            Text(statusText(recording.status))
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            HStack {
                labelDot(.catAction, "Action")
                labelDot(.catDecision, "Decision")
                labelDot(.catQuestion, "Question")
                Spacer()
                Text(recording.duration.asClock)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.accentPurple.opacity(0.20), .accentCyan.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }

    private func row(_ recording: RecordingInfo) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(recording.tag == .meeting ? Color.accentPurple : Color.accentCyan)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title ?? "Untitled session")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("\(recording.tag.rawValue.capitalized) · \(recording.createdAt.mediumFormatted)")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            Text(recording.duration.asClock)
                .font(.caption.monospacedDigit())
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 12)
        .overlay(Divider().background(Color.glassStroke), alignment: .bottom)
    }

    private func labelDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundColor(.textTertiary)
        }
    }

    private func statusText(_ status: PipelineStatus) -> String {
        switch status {
        case .ready: return "AI notes ready. Tap to open transcript and summary."
        case .failed: return "Processing failed. Open to inspect transcript data."
        default: return "Processing status: \(status.rawValue.capitalized)."
        }
    }
}
