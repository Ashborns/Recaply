import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .record
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .record:
                    RecordView()
                case .library:
                    LibraryView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(reduceMotion ? nil : .recaplySpring, value: selectedTab)
    }
}

private enum AppTab: String, CaseIterable {
    case record = "Record"
    case library = "Library"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .record: return "record.circle.fill"
        case .library: return "books.vertical.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        tabItem(tab)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Color.clear.frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color.surfaceDeep.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.glassStroke)
                .frame(height: 1)
        }
        .shadow(color: Color.black.opacity(0.42), radius: 20, x: 0, y: -8)
        .ignoresSafeArea(edges: .bottom)
    }

    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return VStack(spacing: 5) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentGradient)
                        .matchedGeometryEffect(id: "tab-pill", in: namespace)
                }
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .textTertiary)
            }
            .frame(height: 36)

            Text(tab.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundColor(isSelected ? .textPrimary : .textTertiary)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .recaplySpring, value: selectedTab)
    }
}
