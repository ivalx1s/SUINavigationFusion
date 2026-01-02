import Foundation

@MainActor
struct _NavigationRestorationInfo: Hashable, Sendable {
    let key: NavigationDestinationKey
    let payload: Data
}

@MainActor
protocol _NavigationRestorable: NavigationBackGesturePolicyProviding {
    var _restorationInfo: _NavigationRestorationInfo? { get }
}

