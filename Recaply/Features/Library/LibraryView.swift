import SwiftUI

struct LibraryView: View {
    @StateObject private var vm = LibraryViewModel()
    @State private var deleteCandidate: LibraryRecordingCard?
    @State private var showDeleteConfirmation = false

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
                            .contextMenu { deleteButton(for: latest) }
                        ForEach(vm.older) { card in
                            NavigationLink(value: card.id) { row(card) }
                                .buttonStyle(.plain)
                                .contextMenu { deleteButton(for: card) }
                        }
                    } else {
                        EmptyStateView(title: "No recordings yet", message: "Record a meeting or lecture to see AI notes here.")
                    }
                }
                .padding(20)
                .padding(.bottom, 130)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationDestination(for: UUID.self) { id in
                RecordingDetailView(recordingID: id)
            }
            .onAppear { vm.reload() }
            .confirmationDialog("Delete recording?", isPresented: $showDeleteConfirmation) {
                Button("Delete Recording", role: .destructive) {
                    if let deleteCandidate {
                        vm.delete(deleteCandidate)
                        self.deleteCandidate = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    deleteCandidate = nil
                }
            } message: {
                Text("This removes the selected recording and its saved media files.")
            }
        }
    }

    private func heroCard(_ card: LibraryRecordingCard) -> some View {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LATEST · \(card.recording.tag.rawValue.uppercased())")
                    .font(.caption.bold())
                    .foregroundColor(.accentCyan)
                Spacer()
                statusBadge(card.recording.status)
            }
            Text(card.recording.title ?? "Untitled session")
                .font(.title2.bold())
                .foregroundColor(.textPrimary)
            Text(card.preview)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .lineLimit(3)
            HStack {
                labelDot(.catAction, "Action", card.counts[.actionItem, default: 0])
                labelDot(.catDecision, "Decision", card.counts[.decision, default: 0])
                labelDot(.catQuestion, "Question", card.counts[.question, default: 0])
                Spacer()
                Text(card.recording.duration.asClock)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.textTertiary)
            }

            if !card.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open action items")
                        .font(.caption.bold())
                        .foregroundColor(.catAction)
                    ForEach(card.actionItems.prefix(2), id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .background(Color.catAction.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.accentPurple.opacity(0.20), .accentCyan.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
        )
    }

    private func row(_ card: LibraryRecordingCard) -> some View {
        AnyView(
            HStack(spacing: 12) {
            Circle()
                .fill(card.recording.tag == .meeting ? Color.accentPurple : Color.accentCyan)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.recording.title ?? "Untitled session")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("\(card.recording.tag.rawValue.capitalized) · \(card.recording.createdAt.mediumFormatted)")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                Text(card.preview)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(card.recording.duration.asClock)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.textSecondary)
                statusBadge(card.recording.status)
            }
            Button {
                deleteCandidate = card
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.catAction)
                    .frame(width: 32, height: 32)
                    .background(Color.catAction.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
            .overlay(Divider().background(Color.glassStroke), alignment: .bottom)
        )
    }

    private func deleteButton(for card: LibraryRecordingCard) -> some View {
        Button(role: .destructive) {
            deleteCandidate = card
            showDeleteConfirmation = true
        } label: {
            Label("Delete Recording", systemImage: "trash")
        }
    }

    private func labelDot(_ color: Color, _ title: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(title)").font(.caption2).foregroundColor(.textTertiary)
        }
    }

    private func statusBadge(_ status: PipelineStatus) -> some View {
        Text(statusTitle(status))
            .font(.caption2.bold())
            .foregroundColor(status == .ready ? .catDecision : status == .failed ? .catAction : .accentCyan)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func statusTitle(_ status: PipelineStatus) -> String {
        switch status {
        case .ready: return "Ready"
        case .failed: return "Failed"
        default: return status.rawValue.capitalized
        }
    }
}
