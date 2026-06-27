import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            RecordView().tabItem { Label("Record", systemImage: "record.circle.fill") }
            LibraryView().tabItem { Label("Library", systemImage: "books.vertical.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.accentPurple)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct PlaceholderView: View {
    let title: String
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Text(title).font(.title).foregroundColor(.textPrimary)
        }
    }
}
