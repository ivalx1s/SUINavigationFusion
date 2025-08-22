import SwiftUI

extension TopNavigationBar {
    
    // Container that assembles every piece of the bar.
    struct TopBar: View {
        // MARK: Parameters passed from the parent modifier
        let isRoot: Bool
        let hidesBackButton: Bool?
        let leadingView: TopNavigationBarItemView?
        let trailingPrimaryView: TopNavigationBarItemView?
        let trailingSecondaryView: TopNavigationBarItemView?
        let title: String?
        let titleTextView: Text?
        let titleStackSpacing: CGFloat?
        let subtitle: String?
        let currentSubtitleText: Text?
        let navigationBarOpaque: Bool
        
        let pageTransitionProgress: Double
        let onBack: @MainActor () -> Void
        let backButtonIcon: TopNavigationBarConfiguration.BackButtonIconResource?
        
        let titleFont: Font?
        let titleFontWeight: Font.Weight?
        let titleFontColor: Color?
        let subtitleFont: Font?
        let subtitleFontWeight: Font.Weight?
        let subtitleFontColor: Color?
        
        let backgroundMaterial: Material?
        let backgroundColor: Color?
        let scrollDependentBackgroundOpacity: Bool
        let dividerColor: Color?
        
        var body: some View {
            HStack(spacing: 0) {
                BackButton(
                    isRoot: isRoot,
                    hidesBackButton: hidesBackButton,
                    transitionProgressFraction: pageTransitionProgress,
                    onBack: onBack,
                    backButtonIcon: backButtonIcon
                )
                
                if let leadingView {
                    LeadingItem(leading: leadingView, pageTransitionProgress: pageTransitionProgress)
                }
                
                Spacer(minLength: 0)
                
                if let trailingSecondaryView {
                    TrailingSecondary(
                        trailingSecondaryView: trailingSecondaryView,
                        trailingExists: trailingPrimaryView != nil,
                        progress: pageTransitionProgress
                    )
                }
                
                if let trailingPrimaryView {
                    TrailingPrimary(trailing: trailingPrimaryView, pageTransitionProgress: pageTransitionProgress)
                }
            }
            .frame(height: 44)
            .overlay {
                TitleStack(
                    currentTitle: title,
                    titleTextView: titleTextView,
                    titleStackSpacing: titleStackSpacing,
                    subtitle: subtitle,
                    subtitleText: currentSubtitleText,
                    progress: pageTransitionProgress,
                    titleFont: titleFont,
                    titleFontWeight: titleFontWeight,
                    titleFontColor: titleFontColor,
                    subtitleFont: subtitleFont,
                    subtitleFontWeight: subtitleFontWeight,
                    subtitleFontColor: subtitleFontColor
                )
            }
            .background {
                BarBackground(
                    navigationBarOpaque: navigationBarOpaque,
                    backgroundMaterial: backgroundMaterial,
                    backgroundColor: backgroundColor,
                    scrollDependentBackgroundOpacity: scrollDependentBackgroundOpacity,
                    dividerColor: dividerColor
                )
            }
        }
    }
}

// MARK: – Sub‑views
extension TopNavigationBar.TopBar {
    // Back‑navigation button.
    struct BackButton: View {
        let isRoot: Bool
        let hidesBackButton: Bool?
        let transitionProgressFraction: Double
        let onBack: () -> Void
        let backButtonIcon: TopNavigationBarConfiguration.BackButtonIconResource?
        
        private var opacity: Double {
            max(0, 1 - min(transitionProgressFraction / max(0.001, titleProgressThreshold), 1))
        }
        
        var body: some View {
            VStack(spacing: 0) {
                if !isRoot, let hidesBackButton, !hidesBackButton {
                    if let icon = backButtonIcon {
                        Button(action: onBack) {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 38, height: 44)
                                .overlay(alignment: .leading) {
                                    Image(icon.name, bundle: icon.bundle ?? .main)
                                        .renderingMode(.template)
                                        .font(.title2.weight(.medium))
                                        .padding(.leading, 8)
                                }
                                .opacity(opacity)
                        }
                    } else {
                        Button(action: onBack) {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 38, height: 44)
                                .overlay(alignment: .leading) {
                                    Image(systemName: "chevron.backward")
                                        .font(.title2.weight(.medium))
                                        .padding(.leading, 8)
                                }
                                .opacity(opacity)
                        }
                    }
                }
            }
        }
    }
    
    // Leading custom item.
    struct LeadingItem: View {
        let leading: TopNavigationBarItemView
        let pageTransitionProgress: Double
        
        private var opacity: Double {
            max(
                0,
                1 - min(Double(pageTransitionProgress) / max(0.001, titleProgressThreshold), 1)
            )
        }
        
        var body: some View {
            HStack(spacing: 0) {
                leading
                    .equatable()
                    .clipShape(Rectangle())
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .opacity(opacity)
        }
    }
    
    // Secondary (left‑most) trailing item.
    struct TrailingSecondary: View {
        let trailingSecondaryView: TopNavigationBarItemView
        let trailingExists: Bool
        let progress: Double
        
        private var opacity: Double {
            max(
                0,
                1 - min(Double(progress) / max(0.001, titleProgressThreshold), 1)
            )
        }
        
        var body: some View {
            trailingSecondaryView
                .equatable()
                .padding(.trailing, trailingExists ? 4 : 8)
                .opacity(opacity)
        }
    }
    
    // Primary (right‑most) trailing item.
    struct TrailingPrimary: View {
        let trailing: TopNavigationBarItemView
        let pageTransitionProgress: Double
        
        private var opacity: Double {
            max(
                0,
                1 - min(Double(pageTransitionProgress) / max(0.001, titleProgressThreshold), 1)
            )
        }
        
        var body: some View {
            trailing
                .equatable()
                .padding(.trailing, 16)
                .opacity(opacity)
        }
    }
    
    // Title & subtitle stack.
    struct TitleStack: View {
        let currentTitle: String?
        let titleTextView: Text?
        let titleStackSpacing: CGFloat?
        let subtitle: String?
        let subtitleText: Text?
        let progress: Double
        
        let titleFont: Font?
        let titleFontWeight: Font.Weight?
        let titleFontColor: Color?
        let subtitleFont: Font?
        let subtitleFontWeight: Font.Weight?
        let subtitleFontColor: Color?
        
        private var offset: CGFloat { titleHorizontalOffset * progress }
        
        private var opacity: Double {
            max(
                0,
                1 - min(Double(progress) / max(0.001, titleProgressThreshold), 1)
            )
        }
        
        var body: some View {
            VStack(spacing: titleStackSpacing ?? 16) {
                if let titleTextView {
                    titleTextView
                        .offset(x: offset)
                        .opacity(opacity)
                } else if let title = currentTitle {
                    Text(title)
                        .font(
                            (titleFont ?? Font.headline)
                                .weight(titleFontWeight ?? .regular)
                        )
                        .foregroundStyle(titleFontColor ?? Color(uiColor: .label))
                        .offset(x: offset)
                        .opacity(opacity)
                }
                
                if let subtitleText {
                    subtitleText
                        .offset(x: offset)
                        .opacity(opacity)
                } else if let subtitle {
                    Text(subtitle)
                        .font(
                            (subtitleFont ?? Font.subheadline)
                                .weight(subtitleFontWeight ?? .regular)
                        )
                        .foregroundStyle(
                            subtitleFontColor ?? Color(uiColor: .secondaryLabel)
                        )
                        .offset(x: offset)
                        .opacity(opacity)
                }
            }
            .animation(.linear.speed(2), value: progress)
        }
    }
    
    // Background + divider.
    struct BarBackground: View {
        let navigationBarOpaque: Bool
        
        let backgroundMaterial: Material?
        let backgroundColor: Color?
        let scrollDependentBackgroundOpacity: Bool
        let dividerColor: Color?
        
        var body: some View {
            VStack(spacing: 0) {
                if let material = backgroundMaterial {
                    Rectangle()
                        .fill(material)
                        .opacity(
                            scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1
                        )
                        .ignoresSafeArea(.all, edges: .top)
                        .frame(height: 44)
                } else if let color = backgroundColor {
                    Rectangle()
                        .fill(color)
                        .opacity(
                            scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1
                        )
                        .ignoresSafeArea(.all, edges: .top)
                        .frame(height: 44)
                } else {
                    Rectangle()
                        .fill(Material.regular)
                        .opacity(
                            scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1
                        )
                        .ignoresSafeArea(.all, edges: .top)
                        .frame(height: 44)
                }
                
                if let divider = dividerColor {
                    Rectangle()
                        .fill(divider)
                        .opacity(
                            scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1
                        )
                        .frame(height: 0.5)
                }
            }
        }
    }
}


// MARK: – Constants controlling title movement & fade
/// Progress (0…1) after which the title is fully transparent.
private let titleProgressThreshold: Double = 0.5
/// Horizontal offset applied to the title when the gesture completes.
private let titleHorizontalOffset: CGFloat = -50
