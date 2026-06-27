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

/// Runtime CoreML adapter.
///
/// Uses `MLModel` directly instead of referencing the generated Swift type so the
/// app remains compile-safe even before Xcode has generated model classes.
final class CoreMLClassifierProvider: ClassificationProviding {
    static let shared = CoreMLClassifierProvider()

    private let model: MLModel?
    private let inputName: String?
    private let labelOutputName: String?
    private let probabilityOutputName: String?

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "ActionItemClassifier", withExtension: "mlmodelc"),
              let loadedModel = try? MLModel(contentsOf: url) else {
            model = nil
            inputName = nil
            labelOutputName = nil
            probabilityOutputName = nil
            return
        }

        model = loadedModel
        inputName = loadedModel.modelDescription.inputDescriptionsByName.keys.first
        let outputs = loadedModel.modelDescription.outputDescriptionsByName
        labelOutputName = ["label", "classLabel", "class"].first(where: { outputs[$0] != nil }) ?? outputs.keys.first
        probabilityOutputName = ["labelProbability", "classProbability", "probabilities"]
            .first(where: { outputs[$0] != nil })
    }

    var isAvailable: Bool { model != nil }

    func predict(_ text: String) -> (SentenceLabel, Double)? {
        guard let model, let inputName, let labelOutputName else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (.discussion, 0) }

        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [inputName: trimmed])
            let output = try model.prediction(from: input)
            guard let rawLabel = output.featureValue(for: labelOutputName)?.stringValue,
                  let label = SentenceLabel(rawValue: rawLabel) else {
                return nil
            }
            return (label, confidence(for: label, output: output))
        } catch {
            return nil
        }
    }

    private func confidence(for label: SentenceLabel, output: MLFeatureProvider) -> Double {
        guard let probabilityOutputName,
              let dictionary = output.featureValue(for: probabilityOutputName)?.dictionaryValue else {
            return 1.0
        }

        let key = NSString(string: label.rawValue)
        if let value = dictionary[key] as? Double { return value }
        if let number = dictionary[key] { return number.doubleValue }
        return 1.0
    }
}
