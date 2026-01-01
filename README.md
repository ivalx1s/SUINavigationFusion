# SUINavigationFusion

A SwiftUI-first navigation core with a customizable top bar and a thin UIKit bridge.
It hides UINavigationBar, drives your own top bar via environment, and exposes a tiny Navigator API for push/pop.

Requirements
	•	iOS 15+
	•	Swift 5.10+ (supports Swift 6 strict concurrency)

## Installation

Add SUINavigationFusion to your target via Xcode → Package Dependencies and link the product SUINavigationFusion.

## Quick start

```swift
import SwiftUI
import SUINavigationFusion

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationShell(configuration: .defaultMaterial) { navigator in
                InboxScreen()
                    .topNavigationBarTitle("Inbox")
                    .topNavigationBarSubtitle("All messages • 127")
                    .topNavigationBarLeading {
                        Image(systemName: "person.circle.fill").font(.title2)
                    }
                    .topNavigationBarTrailing(position: .secondary) {
                        Button { /* search */ } label: { Image(systemName: "magnifyingglass") }
                    }
                    .topNavigationBarTrailingPrimary {
                        Button { navigator.push(ComposeScreen(), disableBackGesture: true) } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
            }
        }
    }
}
```

## Push/pop with Navigator

```swift
struct InboxScreen: View {
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        List(sampleThreads) { thread in
            Button {
                navigator.push(ThreadScreen(thread: thread))   // animated by default
            } label: { Text(thread.title) }
        }
        .topNavigationBarTitle("Inbox")
    }
}

struct ThreadScreen: View {
    @EnvironmentObject private var navigator: Navigator
    let thread: ThreadModel

    var body: some View {
        ScrollView { /* content */ }
            .topNavigationBarTitle(thread.title)
            .topNavigationBarTrailingPrimary {
                Button("Close") { navigator.pop() }
            }
    }
}
```

## API surface:
	•	push(_ view:animated: Bool = true, disableBackGesture: Bool = false)
	•	pop() / popNonAnimated()
	•	popToRoot(animated: Bool = true)
	•	pop(levels: Int, animated: Bool = true)

## Top bar configuration

Use TopNavigationBarConfiguration to style the bar globally for a navigation stack.

```swift
let config = TopNavigationBarConfiguration(
    backgroundMaterial: .regular,                // or use `backgroundColor:`
    scrollDependentBackgroundOpacity: true,      // background becomes opaque after scroll threshold
    dividerColor: Color.gray.opacity(0.35),
    titleFont: .title3,                          // nil → system default
    titleFontColor: nil,
    subtitleFont: .footnote,
    subtitleFontColor: .secondary,
    titleFontWeight: .semibold,
    subtitleFontWeight: nil,
    titleStackSpacing: 2,
    tintColor: nil,                              // nil → inherit SwiftUI tint (recommended default)
    backButtonIcon: .init(name: "custom_back", bundle: .main) // optional, defaults to chevron
)
```

Apply it when creating the shell:

```swift
NavigationShell(configuration: config) { navigator in
    RootView()
}
```

## Tint (accent) color

By default, SUINavigationFusion does not force a tint: if `TopNavigationBarConfiguration.tintColor == nil`,
the whole navigation stack inherits the surrounding SwiftUI `.tint` (or the system default).

If you set `TopNavigationBarConfiguration.tintColor`, SUINavigationFusion applies it as a SwiftUI `.tint(...)` for the
entire hosted view hierarchy and uses it for bar items (back button + leading/trailing content).

Precedence: configuration `tintColor` → surrounding SwiftUI `.tint` / system.

Note: since the bar is installed outside the screen subtree, a regular `.tint(...)` applied inside a pushed screen does not
reach the bar. Apply `.tint(...)` above `NavigationShell` or set `TopNavigationBarConfiguration.tintColor`.
The bar background is controlled separately via `TopNavigationBarConfiguration.backgroundMaterial` / `backgroundColor`.

## Title & subtitle

Use plain strings: .topNavigationBarTitle("Title"), .topNavigationBarSubtitle("Subtitle") or provide fully styled Text (overrides config fonts/colors):

```swift
.topNavigationBarTitle { Text("Title").kerning(0.5) }
.topNavigationBarSubtitle { Text("Details").foregroundStyle(.secondary) }
```

## Recommended integration pattern (app wrapper + design system)

In production apps, it’s common to keep SUINavigationFusion “clean” and build a tiny wrapper module in your app
that:

- Pins a default `TopNavigationBarConfiguration` (your brand styles).
- Exposes convenience APIs that accept your design-system components (e.g. a standard toolbar button view).
- Optionally injects your design-system theme/context once, at the root.

Example wrapper (rename `AppDesignSystem` / `ToolbarButton` / colors / fonts to match your project):

```swift
import SwiftUI
import SUINavigationFusion
import AppDesignSystem

// periphery:ignore
public extension View {
    // MARK: - App-style top bar wrappers

    func appNavigationBarTitle(_ title: String) -> some View {
        topNavigationBarTitle(title)
    }

    func appNavigationBarTitle(_ text: @escaping () -> Text) -> some View {
        topNavigationBarTitle(text)
    }

    func appNavigationBarSubtitle(_ subtitle: String) -> some View {
        topNavigationBarSubtitle(subtitle)
    }

    func appNavigationBarSubtitle(_ text: @escaping () -> Text) -> some View {
        topNavigationBarSubtitle(text)
    }

    func appNavigationBarHidesBackButton(_ hides: Bool = true) -> some View {
        topNavigationBarHidesBackButton(hides)
    }

    func appNavigationBarLeading(
        id: AnyHashable? = nil,
        updateKey: AnyHashable? = nil,
        @ViewBuilder _ content: () -> AppDesignSystem.ToolbarButton
    ) -> some View {
        topNavigationBarLeading(id: id, updateKey: updateKey, content)
    }
    
    func appNavigationBarTrailing(
        id: AnyHashable? = nil,
        updateKey: AnyHashable? = nil,
        position: TrailingContentPosition = .primary,
        @ViewBuilder _ content: () -> AppDesignSystem.ToolbarButton
    ) -> some View {
        topNavigationBarTrailing(id: id, updateKey: updateKey, position: position, content)
    }
    
    func appNavigationBarPrincipalView<Content: View>(
        id: AnyHashable? = nil,
        updateKey: AnyHashable? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        topNavigationBarPrincipalView(id: id, updateKey: updateKey, content)
    }

    func appToolbarVisibility(
        _ visibility: TopNavigationBarVisibility,
        for section: TopNavigationBarSection
    ) -> some View {
        topNavigationBarVisibility(visibility, for: section)
    }
}

extension TopNavigationBarConfiguration {
    static let appNavigationBarConfiguration: TopNavigationBarConfiguration = {
        TopNavigationBarConfiguration(
            backgroundColor: AppDesignSystem.Colors.backgroundPrimary,
            scrollDependentBackgroundOpacity: false,
            dividerColor: AppDesignSystem.Colors.separator,
            titleFont: AppDesignSystem.Fonts.navigationTitle,
            titleFontColor: AppDesignSystem.Colors.textPrimary,
            subtitleFont: AppDesignSystem.Fonts.navigationSubtitle,
            subtitleFontColor: AppDesignSystem.Colors.textSecondary,
            titleStackSpacing: nil, // use library default
            tintColor: AppDesignSystem.Colors.accent
        )
    }()
}

public struct AppNavigationShell<Root: View>: View {
    private let navigator: Navigator?
    private let rootBuilder: (Navigator) -> Root

    public init(@ViewBuilder root: @escaping (Navigator) -> Root) {
        self.navigator = nil
        self.rootBuilder = root
    }

    public init(navigator: Navigator, @ViewBuilder root: @escaping () -> Root) {
        self.navigator = navigator
        self.rootBuilder = { navigator in root() }
    }

    public var body: some View {
        Group {
            if let navigator {
                NavigationShell(
                    navigator: navigator,
                    configuration: .appNavigationBarConfiguration,
                    root: { rootBuilder(navigator) }
                )
            } else {
                NavigationShell(
                    configuration: .appNavigationBarConfiguration,
                    root: rootBuilder
                )
            }
        }
        .ignoresSafeArea(.all, edges: [.top, .bottom])
    }
}
```

## Leading / trailing items

.topNavigationBarLeading { AvatarView() }
.topNavigationBarTrailing(position: .secondary) { Button { } label: { Image(systemName: "magnifyingglass") } }
.topNavigationBarTrailingPrimary { Button { } label: { Image(systemName: "ellipsis.circle") } }

## Back button
	•	Hidden automatically on the root screen.
	•	Per-screen control: .topNavigationBarHidesBackButton(true)
	•	Disable the interactive back swipe per push:

`navigator.push(Screen(), disableBackGesture: true)`



## Scroll-aware background (optional)

If scrollDependentBackgroundOpacity is true, emit content offset via PositionObservingViewPreferenceKey:

```swift
ScrollView {
    content
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PositionObservingViewPreferenceKey.self,
                    value: CGPoint(x: 0, y: proxy.frame(in: .named("scroll")).minY)
                )
            }
        )
}
.coordinateSpace(name: "scroll")
```

The bar will fade from translucent to opaque as you scroll.

## How it works (in brief)

NavigationShell hosts your root view inside a custom UINavigationController and hides the system bar. A custom top bar is injected via .safeAreaInset(.top, …) and styled through TopNavigationBarConfiguration. Pushes create hosting controllers that receive the same configuration and a transition progress object to sync animations with interactive gestures.


## Sample app

A compact sample showing titles, actions, push/pop, and scroll-aware background:
SUINavigationCore-Sample → https://github.com/ivalx1s/SUINavigationCore-Sample
