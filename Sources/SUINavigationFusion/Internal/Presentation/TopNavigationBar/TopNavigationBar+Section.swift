


extension TopNavigationBar {
    enum Section: Hashable, Codable, Sendable {
        /// Controls visibility of the whole bar container (including safe-area inset + background).
        case bar
        case leading
        case principal
        case trailing
        case trailingPosition(TrailingContentPosition)
    }
}
