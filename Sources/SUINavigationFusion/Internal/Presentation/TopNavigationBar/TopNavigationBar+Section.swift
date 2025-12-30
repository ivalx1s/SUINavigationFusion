


extension TopNavigationBar {
    enum Section: Hashable, Codable, Sendable {
        case leading
        case principal
        case trailing
        case trailingPosition(TrailingContentPosition)
    }
}
