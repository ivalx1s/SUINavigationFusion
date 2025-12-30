import SwiftUI
import Combine

public struct TopNavigationBarConfiguration: Sendable {
    
    /// Represents a custom symbol or image asset used for the navigation back‑button.
    public struct BackButtonIconResource: Sendable {
        /// Asset name or SF Symbol name.
        /// If an image with this name is not found in `bundle`, it will be treated as an SF Symbol name.
        public let name: String
        /// Bundle in which the asset lives. When `nil`, `Bundle.main` is used.
        public let bundle: Bundle?
        
        public init(name: String, bundle: Bundle? = nil) {
            self.name = name
            self.bundle = bundle
        }
    }
    
    /// Material used to fill the bar’s background.
    /// When this value is non‑`nil`, it takes precedence over `backgroundColor`.
    public let backgroundMaterial: Material?
    /// Solid color applied to the bar’s background when `backgroundMaterial` is `nil`.
    public let backgroundColor: Color?
    /// If `true`, the background becomes opaque only after the
    /// scroll position passes a threshold; if `false`, it stays
    /// fully opaque regardless of scrolling.
    public let scrollDependentBackgroundOpacity: Bool
    /// Color of the bottom divider line.
    /// Specify `nil` for no divider.
    public let dividerColor: Color?
    /// Custom font for the navigation‑bar title.
    /// When `nil`, a system default is used.
    public let titleFont: Font?
    /// Color of the title text.
    /// When `nil`, the system default label color is used.
    public let titleFontColor: Color?
    /// Optional weight override for the navigation‑bar title.
    /// When `nil`, the weight embedded in `titleFont` (or the system default) is used.
    public let titleFontWeight: Font.Weight?
    /// Custom font for the navigation‑bar subtitle.
    /// When `nil`, a system default is used.
    public let subtitleFont: Font?
    /// Color of the subtitle text.
    /// When `nil`, the system default secondary label color is used.
    public let subtitleFontColor: Color?
    /// Optional weight override for the navigation‑bar subtitle.
    /// When `nil`, the weight embedded in `subtitleFont` (or the system default) is used.
    public let subtitleFontWeight: Font.Weight?
    /// Spacing applied between the title and subtitle labels.
    /// When `nil`, a default iOS‑like spacing is used (currently `2`).
    public let titleStackSpacing: CGFloat?
    /// Tint color applied to navigation‑bar items (e.g. back button symbol).
    /// When `nil`, the system accent color is used.
    public let tintColor: Color?
    /// Custom icon for the back‑button.
    /// Provide `nil` (default) to use the system chevron.
    public let backButtonIcon: BackButtonIconResource?
    
    public init(
        backgroundMaterial: Material,
        scrollDependentBackgroundOpacity: Bool = false,
        dividerColor: Color? = nil,
        titleFont: Font? = nil,
        titleFontColor: Color? = nil,
        subtitleFont: Font? = nil,
        subtitleFontColor: Color? = nil,
        titleFontWeight: Font.Weight? = nil,
        subtitleFontWeight: Font.Weight? = nil,
        titleStackSpacing: CGFloat? = nil,
        tintColor: Color? = nil,
        backButtonIcon: BackButtonIconResource? = nil
    ) {
        self.backgroundMaterial = backgroundMaterial
        self.backgroundColor = nil
        self.scrollDependentBackgroundOpacity = scrollDependentBackgroundOpacity
        self.dividerColor = dividerColor
        self.titleFont = titleFont
        self.titleFontColor = titleFontColor
        self.subtitleFont = subtitleFont
        self.subtitleFontColor = subtitleFontColor
        self.titleFontWeight = titleFontWeight
        self.subtitleFontWeight = subtitleFontWeight
        self.titleStackSpacing = titleStackSpacing
        self.tintColor = tintColor
        self.backButtonIcon = backButtonIcon
    }
    
    public init(
        backgroundColor: Color,
        scrollDependentBackgroundOpacity: Bool = false,
        dividerColor: Color? = nil,
        titleFont: Font? = nil,
        titleFontColor: Color? = nil,
        subtitleFont: Font? = nil,
        subtitleFontColor: Color? = nil,
        titleFontWeight: Font.Weight? = nil,
        subtitleFontWeight: Font.Weight? = nil,
        titleStackSpacing: CGFloat? = nil,
        tintColor: Color?,
        backButtonIcon: BackButtonIconResource? = nil
    ) {
        self.backgroundMaterial = nil
        self.backgroundColor = backgroundColor
        self.scrollDependentBackgroundOpacity = scrollDependentBackgroundOpacity
        self.dividerColor = dividerColor
        self.titleFont = titleFont
        self.titleFontColor = titleFontColor
        self.subtitleFont = subtitleFont
        self.subtitleFontColor = subtitleFontColor
        self.titleFontWeight = titleFontWeight
        self.subtitleFontWeight = subtitleFontWeight
        self.titleStackSpacing = titleStackSpacing
        self.tintColor = tintColor
        self.backButtonIcon = backButtonIcon
    }
    
    /// A convenient preset that mimics the native translucent navigation bar.
    /// - Uses `.regular` `Material` for the background.
    /// - Keeps the divider visible with 50 % gray opacity.
    /// - Dynamic background opacity as the user scrolls
    public static let defaultMaterial: TopNavigationBarConfiguration = {
        TopNavigationBarConfiguration(
            backgroundMaterial: Material.regular,
            scrollDependentBackgroundOpacity: true,
            dividerColor: Color.gray.opacity(0.5),
            titleFont: nil,
            titleFontColor: nil,
            subtitleFont: nil,
            subtitleFontColor: nil,
            titleFontWeight: nil,
            subtitleFontWeight: nil,
            titleStackSpacing: nil,
            tintColor: nil,
            backButtonIcon: nil
        )
    }()
}
