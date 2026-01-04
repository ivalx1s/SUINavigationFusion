import Foundation

/// Selects which trailing slot to use when providing top bar content.
///
/// The top bar supports up to two trailing items:
/// - `.primary` is the rightmost item
/// - `.secondary` is placed to the left of the primary item
public enum TrailingContentPosition: Hashable, Codable, Sendable {
    case primary
    case secondary
}
