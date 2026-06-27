import Foundation

enum SessionTag: String, Codable, CaseIterable {
    case meeting, lecture

    var title: String {
        switch self {
        case .meeting: return "Meeting"
        case .lecture: return "Lecture"
        }
    }

    var shortDescription: String {
        switch self {
        case .meeting: return "Best for team syncs, decisions, and follow-up tasks."
        case .lecture: return "Best for classes, explanations, concepts, and study notes."
        }
    }

    var iconName: String {
        switch self {
        case .meeting: return "person.2.fill"
        case .lecture: return "graduationcap.fill"
        }
    }
}
