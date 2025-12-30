import SwiftUI


// MARK: – Nav-bar modifier
struct TopNavigationBar: ViewModifier {
    @EnvironmentObject private var navigationPageTransitionProgress: NavigationPageTransitionProgress
    @EnvironmentObject private var navigator: Navigator
    
    @Environment(\.topNavigationBarConfiguration) private var topNavigationBarConfiguration
    
    // Latest values coming from child views
    @State private var title: String?  = nil
    @State private var subtitle: String?  = nil
    @State private var leadingView: TopNavigationBarItemView? = nil
    @State private var trailingPrimaryView: TopNavigationBarItemView? = nil
    @State private var trailingSecondaryView: TopNavigationBarItemView? = nil
    @State private var hidesBackButton: Bool? = false
    
    @State private var titleTextView: Text? = nil
    @State private var currentSubtitleText: Text? = nil
    
    @State private var principalView: TopNavigationPrincipalView? = nil
    
    /// `true` when the scroll-view’s content has moved under the bar
    @State private var navigationBarOpaque = false
    
    @State private var visibility: [Section: TopNavigationBar.ComponentVisibility] = [:]
    
    let isRoot: Bool
    
    func body(content: Content) -> some View {
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
                .tint(topNavigationBarConfiguration.tintColor)
                .accentColor(topNavigationBarConfiguration.tintColor)
            }
            .onPreferenceChange(TopNavigationBarTitlePreferenceKey.self) { title in
                Task { @MainActor in self.title = title }
            }
            .onPreferenceChange(TopNavigationBarLeadingPreferenceKey.self)  { viewWrap in
                Task { @MainActor in leadingView = viewWrap }
            }
            .onPreferenceChange(TopNavigationBarTrailingPrimaryPreferenceKey.self) { viewWrap in
                Task { @MainActor in trailingPrimaryView = viewWrap }
            }
            .onPreferenceChange(TopNavigationBarTrailingSecondaryPreferenceKey.self) { viewWrap in
                Task { @MainActor in trailingSecondaryView = viewWrap }
            }
            .onPreferenceChange(TopNavigationBarHidesBackButtonPreferenceKey.self) { hides in
                Task { @MainActor in hidesBackButton = hides  }
            }
            .onPreferenceChange(TopNavigationBarSubtitlePreferenceKey.self) { subtitle in
                Task { @MainActor in self.subtitle = subtitle }
            }
            .onPreferenceChange(TopNavigationBarSubtitleTextPreferenceKey.self) { subtitleText in
                Task { @MainActor in self.currentSubtitleText = subtitleText  }
            }
            .onPreferenceChange(TopNavigationBarTitleTextPreferenceKey.self) { titleTextView in
                Task { @MainActor in self.titleTextView = titleTextView }
            }
            .onPreferenceChange(TopNavigationBarPrincipalViewPreferenceKey.self) { principalView in
                Task { @MainActor in self.principalView = principalView }
            }
            .onPreferenceChange(
                PositionObservingViewPreferenceKey.self,
                perform: processScrollOffset
            )
            .onPreferenceChange(TopNavigationBarVisibilityPreferenceKey.self) { visibility in
                if let visibility {
                    Task { @MainActor in self.visibility = visibility }
                }
            }
    }
    
    /// Handles scroll‑offset changes coming from `PositionObservingViewPreferenceKey`.
    nonisolated private func processScrollOffset(_ offset: CGPoint) {
        Task { @MainActor in
            // If background opacity should not depend on scroll,
            // keep background always visible and skip further calculations.
            if !topNavigationBarConfiguration.scrollDependentBackgroundOpacity {
                navigationBarOpaque = true
                return
            }
            
            let shouldBeOpaque = offset.y < -0.2
            if shouldBeOpaque != navigationBarOpaque {
                withAnimation(.linear(duration: 0.05)) {
                    navigationBarOpaque = shouldBeOpaque
                }
            }
        }
    }
}
