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
	•	push(route:animated: Bool = true, disableBackGesture: Bool = false)
	•	pop() / popNonAnimated()
	•	popToRoot(animated: Bool = true)
	•	pop(levels: Int, animated: Bool = true)
	•	clearCachedStack()

## Navigation stack restoration (state caching)

`Navigator.push(_ view:)` accepts arbitrary SwiftUI views, which are not serializable. If you want navigation stack
restoration, push a serializable `NavigationRoute` instead:

- Use `RestorableNavigationShell` (Option 3) for a single route type (usually an enum).
- Use `PathRestorableNavigationShell` (Option 4) for a modular, registry-driven setup (NavigationPath-like).

Only `navigator.push(route:)` participates in restoration. `navigator.push(_ view:)` is treated as transient.

### Robustness recommendations (read this before shipping)

- **Use explicit stable destination keys.** Keys are persisted, so avoid type-derived keys for long-lived data.
  - Option 3: pass `key:` explicitly.
  - Option 4: register with explicit per-destination keys (e.g. `"thread"`, `"settings"`).
  - `.type(...)` exists for convenience and applies best-effort normalization, but it remains refactor-sensitive.
- **Support renames with `aliases:`.** If you rename a key, keep the old key in `aliases:` so existing persisted stacks still restore.
- **Make `id:` scene-unique for multi-window apps.** Each window/scene needs its own persisted stack id; otherwise multiple scenes overwrite each other in the store.
  - Use `idScope: .scene` for automatic per-scene scoping (recommended).
- **Treat your route payload as a persisted schema.** Avoid breaking `Codable` changes, or keep backward-compatible decoding (versioning/migrations).
  - If you need stable date/key strategies, pass custom `encoder:` / `decoder:` into the restorable shell.

### Option 3 — single `Route` type (recommended for small apps)

```swift
import SUINavigationFusion

enum AppRoute: NavigationRoute {
    case thread(id: String)
    case settings
}

RestorableNavigationShell<AppRoute>(
    id: "mainStack",
    key: "com.myapp.mainRoute",
    aliases: [.type(AppRoute.self)], // optional: keep if you previously shipped the default key
    configuration: .defaultMaterial,
    root: { _ in InboxScreen() },
    destination: { route in
        switch route {
        case .thread(let id): ThreadScreen(id: id)
        case .settings: SettingsScreen()
        }
    }
)
```

Push a route:

```swift
navigator.push(route: AppRoute.thread(id: "123"))
```

### Option 4 — registry-driven (recommended for modular apps)

```swift
import SUINavigationFusion

struct ThreadRoute: NavigationRoute { let id: String }
struct SettingsRoute: NavigationRoute { init() {} }

PathRestorableNavigationShell(
    id: "mainStack",
    destinations: { registry in
        registry.register(ThreadRoute.self, key: "com.myapp.thread") { route in
            ThreadScreen(id: route.id)
        }
        registry.register(SettingsRoute.self, key: "com.myapp.settings") { _ in
            SettingsScreen()
        }
    },
    root: { _ in InboxScreen() }
)
```

`destinations` is a configuration closure: it is called once to register all destinations for this stack by mutating the
provided registry via `registry.register(...)` (avoid side effects).

Push a payload type:

```swift
navigator.push(route: ThreadRoute(id: "123"))
```

### What is persisted

- The route payload (`Codable`) for every `push(route:)`.
- `disableBackGesture` flag per entry.

### What is NOT persisted

- SwiftUI local state (`@State`, scroll position, focus, etc.). Reconstruct those from your route payload if needed.
- Top bar titles / items (they are derived from each screen’s SwiftUI preferences).

### Mixing route pushes and view pushes

You can mix `push(route:)` and `push(_ view:)`, but restoration can only rebuild the prefix of the stack that is
fully route-backed. A transient `push(_ view:)` above root truncates the persisted snapshot for everything above it.

### Clearing cached state

Call `navigator.clearCachedStack()` to remove the persisted snapshot for the current restorable shell.

### Scene-unique stack ids (multi-window)

If your app supports multiple windows/scenes, use `idScope: .scene` to automatically scope snapshots per scene/window:

```swift
RestorableNavigationShell<AppRoute>(
    id: "catalog",
    idScope: .scene,
    key: "com.myapp.catalogRoute",
    root: { _ in CatalogRootScreen() },
    destination: { route in
        /* ... */
    }
)
```

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
the navigation stack uses the system default tint.

If you set `TopNavigationBarConfiguration.tintColor`, SUINavigationFusion applies it as a SwiftUI `.tint(...)` for the
entire hosted view hierarchy and uses it for bar items (back button + leading/trailing content).

Precedence: configuration `tintColor` → system.

Note: since the bar is installed outside the screen subtree, per-screen tinting is intentionally not supported.
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
