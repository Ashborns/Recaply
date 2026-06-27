import SwiftUI

@main
struct RecaplyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
        }
    }
}
