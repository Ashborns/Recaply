import Foundation

extension Date {
    var mediumFormatted: String {
        self.formatted(date: .abbreviated, time: .shortened)
    }
}
