import Foundation
import CoreML

protocol ClassificationProviding {
    /// Returns (label, confidence), or nil if no model is available.
    func predict(_ text: String) -> (SentenceLabel, Double)?
}

/// Stub used until the trained `.mlmodel` is dropped in at the lab.
struct StubClassifierProvider: ClassificationProviding {
    func predict(_ text: String) -> (SentenceLabel, Double)? { nil }
}

/// Adapter point for the generated CoreML model.
///
/// The trained model is added during lab verification as
/// `Recaply/Resources/Models/ActionItemClassifier.mlmodel`. Until then, the app
/// defaults to `StubClassifierProvider`, so this wrapper intentionally avoids
/// referencing the generated Swift model type and stays compile-safe.
final class CoreMLClassifierProvider: ClassificationProviding {
    static let shared = CoreMLClassifierProvider()

    private let modelURL: URL?

    init(bundle: Bundle = .main) {
        modelURL = bundle.url(forResource: "ActionItemClassifier", withExtension: "mlmodelc")
    }

    var isAvailable: Bool { modelURL != nil }

    func predict(_ text: String) -> (SentenceLabel, Double)? {
        // Lab hook: once the .mlmodel exists, replace this method with the generated
        // `ActionItemClassifier(configuration:)` wrapper and map its output label.
        nil
    }
}
