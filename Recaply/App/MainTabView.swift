import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            PlaceholderView("Record").tabItem { Label("Record", systemImage: "record.circle.fill") }
            PlaceholderView("Library").tabItem { Label("Library", systemImage: "books.vertical.fill") }
            PlaceholderView("Settings").tabItem { Label("Settings", systemImage: "gearshape.fill") }
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
