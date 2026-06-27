import CoreData

/// Core Data stack for local-only storage (recordings, transcripts, summaries).
/// Single shared container; `viewContext` is injected into the SwiftUI environment
/// at app launch. Pola FitnessApp / NovelDex.
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Recaply")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error { NSLog("Core Data load error: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var viewContext: NSManagedObjectContext { container.viewContext }
}
