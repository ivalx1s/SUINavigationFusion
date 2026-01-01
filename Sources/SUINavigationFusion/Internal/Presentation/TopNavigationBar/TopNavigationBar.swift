import SwiftUI


// MARK: – Nav-bar modifier
@MainActor
struct TopNavigationBar: ViewModifier {
    @EnvironmentObject private var navigationPageTransitionProgress: NavigationPageTransitionProgress
    @EnvironmentObject private var navigator: Navigator
    
    @EnvironmentObject private var configurationStore: TopNavigationBarConfigurationStore
    
    // Latest values coming from child views
    @State private var title: String?  = nil
    @State private var subtitle: String?  = nil
    @State private var leadingView: TopNavigationBarItem? = nil
    @State private var trailingPrimaryView: TopNavigationBarItem? = nil
    @State private var trailingSecondaryView: TopNavigationBarItem? = nil
    @State private var hidesBackButton: Bool? = false
    
    @State private var titleTextView: Text? = nil
    @State private var currentSubtitleText: Text? = nil
    
    @State private var principalView: TopNavigationBarPrincipal? = nil
    
    /// `true` when the scroll-view’s content has moved under the bar
    @State private var navigationBarOpaque = false
    
    @State private var visibility: [Section: TopNavigationBar.ComponentVisibility] = [:]
    
    let isRoot: Bool
    
    func body(content: Content) -> some View {
        let topNavigationBarConfiguration = configurationStore.configuration

        // NOTE: Avoid conditional view branching for tint application.
        // In SwiftUI, changing the "shape" of the view tree (e.g. applying `.tint` only sometimes)
        // can reset state in surprising places (TabView selections, navigation stacks, etc.).
        //
        // We always apply `.tint` using either the configuration tint (when non-nil)
        // or `Color.accentColor` as a dynamic "inherit from environment/system" fallback.
        let resolvedTint: Color = topNavigationBarConfiguration.tintColor ?? .accentColor

        content
            .navigationBarHidden(true)
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top, spacing: .zero) {
                //  Custom top bar view, applied through inset semantics to support scroll-through behavior
                TopBar(
                    isRoot: isRoot,
                    hidesBackButton: hidesBackButton,
                    leadingView: leadingView,
                    trailingPrimaryView: trailingPrimaryView,
                    trailingSecondaryView: trailingSecondaryView,
                    title: title,
                    titleTextView: titleTextView,
                    principalView: principalView,
                    titleStackSpacing: topNavigationBarConfiguration.titleStackSpacing,
                    subtitle: subtitle,
                    currentSubtitleText: currentSubtitleText,
                    navigationBarOpaque: navigationBarOpaque,
                    visibility: visibility,
                    pageTransitionProgress: navigationPageTransitionProgress.progress,
                    onBack: navigator.pop,
                    backButtonIcon: topNavigationBarConfiguration.backButtonIcon,
                    itemTintColor: resolvedTint,
                    titleFont: topNavigationBarConfiguration.titleFont,
                    titleFontWeight: topNavigationBarConfiguration.titleFontWeight,
                    titleFontColor: topNavigationBarConfiguration.titleFontColor,
                    subtitleFont: topNavigationBarConfiguration.subtitleFont,
                    subtitleFontWeight: topNavigationBarConfiguration.subtitleFontWeight,
                    subtitleFontColor: topNavigationBarConfiguration.subtitleFontColor,
                    backgroundMaterial: topNavigationBarConfiguration.backgroundMaterial,
                    backgroundColor: topNavigationBarConfiguration.backgroundColor,
                    scrollDependentBackgroundOpacity: topNavigationBarConfiguration.scrollDependentBackgroundOpacity,
                    dividerColor: topNavigationBarConfiguration.dividerColor
                )
                .tint(resolvedTint)
                .accentColor(resolvedTint)
            }
            .onPreferenceChange(TopNavigationBarTitlePreferenceKey.self) { title in
                self.title = title
            }
            .onPreferenceChange(TopNavigationBarLeadingPreferenceKey.self)  { viewWrap in
                leadingView = viewWrap
            }
            .onPreferenceChange(TopNavigationBarTrailingPrimaryPreferenceKey.self) { viewWrap in
                trailingPrimaryView = viewWrap
            }
            .onPreferenceChange(TopNavigationBarTrailingSecondaryPreferenceKey.self) { viewWrap in
                trailingSecondaryView = viewWrap
            }
            .onPreferenceChange(TopNavigationBarHidesBackButtonPreferenceKey.self) { hides in
                hidesBackButton = hides
            }
            .onPreferenceChange(TopNavigationBarSubtitlePreferenceKey.self) { subtitle in
                self.subtitle = subtitle
            }
            .onPreferenceChange(TopNavigationBarSubtitleTextPreferenceKey.self) { subtitleText in
                self.currentSubtitleText = subtitleText
            }
            .onPreferenceChange(TopNavigationBarTitleTextPreferenceKey.self) { titleTextView in
                self.titleTextView = titleTextView
            }
            .onPreferenceChange(TopNavigationBarPrincipalViewPreferenceKey.self) { principalView in
                self.principalView = principalView
            }
            .onPreferenceChange(
                PositionObservingViewPreferenceKey.self,
                perform: processScrollOffset
            )
            .onPreferenceChange(TopNavigationBarVisibilityPreferenceKey.self) { visibility in
                if let visibility {
                    self.visibility = visibility
                }
            }
    }
    
    /// Handles scroll‑offset changes coming from `PositionObservingViewPreferenceKey`.
    private func processScrollOffset(_ offset: CGPoint) {
        let topNavigationBarConfiguration = configurationStore.configuration

        // If background opacity should not depend on scroll,
        // keep background always visible and skip further calculations.
        if !topNavigationBarConfiguration.scrollDependentBackgroundOpacity {
            navigationBarOpaque = true
            return
        }
        
        let shouldBeOpaque = offset.y < -0.2
        if shouldBeOpaque != navigationBarOpaque {
            navigationBarOpaque = shouldBeOpaque
        }
    }
}
