import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension TopNavigationBar {
    
    // Контейнер, собирающий все части бара.
    struct TopBar: View {
        // MARK: Параметры, передаваемые из модификатора
        let isRoot: Bool
        let hidesBackButton: Bool?
        let leadingView: TopNavigationBarItem?
        let trailingPrimaryView: TopNavigationBarItem?
        let trailingSecondaryView: TopNavigationBarItem?
        let title: String?
        let titleTextView: Text?
        let principalView: TopNavigationBarPrincipal?
        let titleStackSpacing: CGFloat?
        let subtitle: String?
        let currentSubtitleText: Text?
        let navigationBarOpaque: Bool
        let visibility: [TopNavigationBar.Section: TopNavigationBar.ComponentVisibility]
        
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
        
        // MARK: - Измеренные ширины боковых кластеров
        @State private var leftWidth:  CGFloat = 0
        @State private var rightWidth: CGFloat = 0
        
        // Базовые системные поля, как у UINavigationBar.
        private let baseInset: CGFloat = 16
        
        // Есть ли back?
        private var showsBack: Bool {
            (!isRoot) && ((hidesBackButton ?? false) == false)
        }
        
        private var leftInset: CGFloat { baseInset }
        private var rightInset: CGFloat { baseInset }
        
        // Чтобы заголовок оставался строго по центру, вырезаем с обеих сторон
        private var symmetricGuard: CGFloat { max(leftWidth + leftInset, rightWidth + rightInset) }
        
        var body: some View {
            ZStack {
                // --- Центр (title / principal)
                Group {
                    if visibility[.principal] != .hidden, let principalView {
                        principalView.view
                            .frame(maxWidth: .infinity)
                    } else {
                        TitleStack(
                            currentTitle: title,
                            titleTextView: titleTextView,
                            spacingOverride: titleStackSpacing ?? 2,
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
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
                    }
                }
                .padding(.leading,  symmetricGuard)
                .padding(.trailing, symmetricGuard)
                .frame(height: 44)
                
                // --- Боковые кластеры поверх центра
                HStack(spacing: 0) {
                    LeftCluster(
                        isRoot: isRoot,
                        hidesBackButton: hidesBackButton,
                        progress: pageTransitionProgress,
                        onBack: onBack,
                        backButtonIcon: backButtonIcon,
                        leadingView: leadingView,
                        isLeadingViewVisible: visibility[.leading] != .hidden
                    )
                    .background(WidthReader(key: LeftWidthKey.self))   // измеряем ширину слева
                    
                    Spacer(minLength: 0)
                    
                    RightCluster(
                        progress: pageTransitionProgress,
                        trailingPrimaryView: trailingPrimaryView,
                        trailingSecondaryView: trailingSecondaryView,
                        visibility: visibility
                    )
                    .background(WidthReader(key: RightWidthKey.self))  // измеряем ширину справа
                }
                // разные поля слева/справа — но центр всё равно останется по центру,
                // т.к. выше мы используем symmetricGuard.
                .padding(.leading, leftInset)
                .padding(.trailing, rightInset)
                .frame(height: 44)
            }
            .frame(height: 44)
            .onPreferenceChange(LeftWidthKey.self)  { leftWidth  = $0 }
            .onPreferenceChange(RightWidthKey.self) { rightWidth = $0 }
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

// MARK: – Локальные preference keys для измерения ширины
private struct LeftWidthKey: @MainActor PreferenceKey {
    @MainActor static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
private struct RightWidthKey: @MainActor PreferenceKey {
    @MainActor static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Прозрачный измеритель ширины.
private struct WidthReader<K: PreferenceKey>: View where K.Value == CGFloat {
    var key: K.Type
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: key, value: proxy.size.width)
        }
    }
}

// MARK: – Sub-views
extension TopNavigationBar.TopBar {
    // Кнопка назад.
    struct BackButton: View {
        let isRoot: Bool
        let hidesBackButton: Bool?
        let transitionProgressFraction: Double
        let onBack: () -> Void
        let backButtonIcon: TopNavigationBarConfiguration.BackButtonIconResource?
        
        private var opacity: Double {
            // TODO: PMA-17561
//            max(0, 1 - min(transitionProgressFraction / max(0.001, titleProgressThreshold), 1))
            1
        }
        
        var body: some View {
            Group {
                if !isRoot, let hidesBackButton, !hidesBackButton {
                    if let icon = backButtonIcon {
                        Button(action: onBack) {
                            // Зона тапа 38×44, без внутренних сдвигов — чтобы левая грань
                            // иконки визуально совпала с полем контейнера.
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 38, height: 44)
                                .overlay(alignment: .leading) {
                                    backIcon(for: icon)
                                        .renderingMode(.template)
                                        .font(.title2.weight(.medium))
                                }
                                .foregroundStyle(.tint)
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
                                }
                                .foregroundStyle(.tint)
                                .opacity(opacity)
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }

        private func backIcon(for icon: TopNavigationBarConfiguration.BackButtonIconResource) -> Image {
#if canImport(UIKit)
            if let uiImage = UIImage(named: icon.name, in: icon.bundle, compatibleWith: nil) {
                return Image(uiImage: uiImage)
            }
            return Image(systemName: icon.name)
#else
            return Image(icon.name, bundle: icon.bundle)
#endif
        }
    }
    
    // Левый кластер = Back + кастомный leading (измеряются вместе).
    private struct LeftCluster: View {
        let isRoot: Bool
        let hidesBackButton: Bool?
        let progress: Double
        let onBack: () -> Void
        let backButtonIcon: TopNavigationBarConfiguration.BackButtonIconResource?
        let leadingView: TopNavigationBarItem?
        let isLeadingViewVisible: Bool
        
        private var showsBack: Bool {
            (!isRoot) && ((hidesBackButton ?? false) == false)
        }
        
        var body: some View {
            HStack(spacing: 0) {
                BackButton(
                    isRoot: isRoot,
                    hidesBackButton: hidesBackButton,
                    transitionProgressFraction: progress,
                    onBack: onBack,
                    backButtonIcon: backButtonIcon
                )
                
                if isLeadingViewVisible, let leadingView {
                    LeadingItem(
                        leading: leadingView,
                        pageTransitionProgress: progress,
                        hasBackButton: showsBack
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    // Правый кластер = secondary + primary (измеряются вместе).
    private struct RightCluster: View {
        let progress: Double
        let trailingPrimaryView: TopNavigationBarItem?
        let trailingSecondaryView: TopNavigationBarItem?
        let visibility: [TopNavigationBar.Section: TopNavigationBar.ComponentVisibility]
        
        var body: some View {
            HStack(spacing: 16) {
                let hideAllTrailing = visibility[.trailing] == .hidden
                
                if !hideAllTrailing,
                   visibility[.trailingPosition(.secondary)] != .hidden,
                   let trailingSecondaryView {
                    TrailingSecondary(
                        trailingSecondaryView: trailingSecondaryView,
                        progress: progress
                    )
                }
                
                if !hideAllTrailing,
                   visibility[.trailingPosition(.primary)] != .hidden,
                   let trailingPrimaryView {
                    TrailingPrimary(trailing: trailingPrimaryView, pageTransitionProgress: progress)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    // Кастомный leading-элемент.
    struct LeadingItem: View {
        let leading: TopNavigationBarItem
        let pageTransitionProgress: Double
        let hasBackButton: Bool
        
        private var opacity: Double {
            // TODO: PMA-17561
//            max(0, 1 - min(Double(pageTransitionProgress) / max(0.001, titleProgressThreshold), 1))
            1
        }
        
        var body: some View {
            TopNavigationBarItemContent(item: leading)
            // Если рядом есть back — небольшой зазор 4pt между back и leading.
                .padding(.leading, hasBackButton ? 4 : 0)
                .opacity(opacity)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    // Вторичный (левее) элемент справа.
    struct TrailingSecondary: View {
        let trailingSecondaryView: TopNavigationBarItem
        let progress: Double
        
        private var opacity: Double {
            // TODO: PMA-17561
//            max(0, 1 - min(Double(progress) / max(0.001, titleProgressThreshold), 1))
            1
        }
        
        var body: some View {
            TopNavigationBarItemContent(item: trailingSecondaryView)
                .opacity(opacity)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    // Основной (правее всех) элемент справа.
    struct TrailingPrimary: View {
        let trailing: TopNavigationBarItem
        let pageTransitionProgress: Double
        
        private var opacity: Double {
            // TODO: PMA-17561
//            max(0, 1 - min(Double(pageTransitionProgress) / max(0.001, titleProgressThreshold), 1))
            1
        }
        
        var body: some View {
            TopNavigationBarItemContent(item: trailing)
            // Без доп. трэйлинга — дистанцию до края контролирует rightInset контейнера.
                .opacity(opacity)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    // Заголовок и подзаголовок.
    struct TitleStack: View {
        let currentTitle: String?
        let titleTextView: Text?
        let spacingOverride: CGFloat
        let subtitle: String?
        let subtitleText: Text?
        let progress: Double
        
        let titleFont: Font?
        let titleFontWeight: Font.Weight?
        let titleFontColor: Color?
        let subtitleFont: Font?
        let subtitleFontWeight: Font.Weight?
        let subtitleFontColor: Color?
        
        private var opacity: Double {
            // TODO: PMA-17561
//            max(0, 1 - min(Double(progress) / max(0.001, titleProgressThreshold), 1))
            1
        }
        
        var body: some View {
            VStack(spacing: spacingOverride) {
                if let titleTextView {
                    titleTextView
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(opacity)
                        .multilineTextAlignment(.center)
                } else if let title = currentTitle {
                    Text(title)
                        .font((titleFont ?? .headline).weight(titleFontWeight ?? .regular))
                        .foregroundStyle(titleFontColor ?? Color(uiColor: .label))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(opacity)
                        .multilineTextAlignment(.center)
                }
                
                if let subtitleText {
                    subtitleText
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(opacity)
                        .multilineTextAlignment(.center)
                } else if let subtitle {
                    Text(subtitle)
                        .font((subtitleFont ?? .subheadline).weight(subtitleFontWeight ?? .regular))
                        .foregroundStyle(subtitleFontColor ?? Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(opacity)
                        .multilineTextAlignment(.center)
                }
            }
            .animation(.linear.speed(2), value: progress)
        }
    }
    
    // Фон + разделитель.
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
                        .opacity(scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1)
                        .ignoresSafeArea(.all, edges: .top)
                        .frame(height: 44)
                } else if let color = backgroundColor {
                    Rectangle()
                        .fill(color)
                        .opacity(scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1)
                        .ignoresSafeArea(.all, edges: .top)
                        .frame(height: 44)
                } else {
                    Rectangle()
                        .fill(Material.regular)
                        .opacity(scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1)
                        .ignoresSafeArea(.all, edges: .top)
                        .frame(height: 44)
                }
                
                if let divider = dividerColor {
                    Rectangle()
                        .fill(divider)
                        .opacity(scrollDependentBackgroundOpacity ? (navigationBarOpaque ? 1 : 0) : 1)
                        .frame(height: 0.5)
                }
            }
        }
    }
    
}

// MARK: – Константы анимации заголовка
/// Прогресс (0…1), после которого заголовок полностью прозрачный.
private let titleProgressThreshold: Double = 0.5
