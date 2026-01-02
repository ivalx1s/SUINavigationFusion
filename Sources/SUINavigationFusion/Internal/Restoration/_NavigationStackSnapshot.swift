import Foundation

struct _NavigationStackSnapshot: Codable, Sendable, Equatable {
    var schemaVersion: Int = 1
    var entries: [Entry]

    struct Entry: Codable, Hashable, Sendable {
        var key: NavigationDestinationKey
        var payload: Data
        var disableBackGesture: Bool
    }
}

