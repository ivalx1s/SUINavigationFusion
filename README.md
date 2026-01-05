# SUINavigationFusion

A SwiftUI-first navigation core with a customizable top bar and a thin UIKit bridge.
It hides UINavigationBar, drives your own top bar via environment, and exposes a tiny Navigator API for push/pop.

## Requirements

- iOS 15+
- Swift 5.10+ (supports Swift 6 strict concurrency)

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

## API surface

- `push(_:animated:disableBackGesture:transition:)`
- `push(route:animated:disableBackGesture:transition:)` (route must be `NavigationPathItem`)
- `pop()` / `popNonAnimated()`
- `popToRoot(animated:)`
- `pop(levels:animated:)`
- `clearCachedStack()`

## Typed route navigation (registry)

`Navigator.push(route:)` requires a typed destination registry installed by one of:

- `TypedNavigationShell` (typed routing only)
- `PathRestorableNavigationShell` / `RestorableNavigationShell` (typed routing + persistence)

Feature modules can decouple from a concrete stack by exporting a `NavigationDestinations` bundle:

```swift
// Feature module
public struct ThreadRoute: NavigationPathItem {
    public static let destinationKey: NavigationDestinationKey = "com.myapp.thread"
    public let id: String
}

public enum ThreadFeatureNavigation {
    public static let destinations = NavigationDestinations { registry in
        // Uses `ThreadRoute.destinationKey` as the persisted key.
        registry.register(ThreadRoute.self) { route in
            ThreadScreen(id: route.id)
        }
    }
}
```

Compose bundles at the app root:

```swift
let destinations = ThreadFeatureNavigation.destinations
    .merging(SettingsFeatureNavigation.destinations)

TypedNavigationShell(
    destinations: destinations,
    root: { _ in InboxScreen() }
)
```

## Navigation stack restoration (state caching)

`Navigator.push(_ view:)` accepts arbitrary SwiftUI views, which are not serializable. If you want navigation stack
restoration (and/or path-driven navigation), push a serializable route payload via `navigator.push(route:)`.

Route payloads should conform to `NavigationPathItem` so they have a stable persisted destination key.

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

enum AppRoute: NavigationPathItem {
    static let destinationKey: NavigationDestinationKey = "com.myapp.mainRoute"

    case thread(id: String)
    case settings
}

RestorableNavigationShell<AppRoute>(
    id: "mainStack",
    key: AppRoute.destinationKey,
    configuration: .defaultMaterial,
    additionalDestinations: ThreadFeatureNavigation.destinations, // optional
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

struct ThreadRoute: NavigationPathItem {
    static let destinationKey: NavigationDestinationKey = "com.myapp.thread"
    let id: String
}
struct SettingsRoute: NavigationPathItem {
    static let destinationKey: NavigationDestinationKey = "com.myapp.settings"
    init() {}
}

PathRestorableNavigationShell(
    id: "mainStack",
    destinations: ThreadFeatureNavigation.destinations
        .merging(SettingsFeatureNavigation.destinations),
    root: { _ in InboxScreen() }
)
```

`destinations` is applied once to register all destinations for this stack by mutating the registry via
`registry.register(...)` (avoid side effects).

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

## Path-driven navigation (NavigationStack-like)

If you want an external router/coordinator to own navigation state (similar to SwiftUI’s `NavigationStack(path:)`),
bind a `SUINavigationPath` into a restorable shell using `path:`.

In this mode:
- The shell reconciles the UIKit stack to match the bound `SUINavigationPath`.
- Interactive swipe-back updates the bound path (UIKit stack is authoritative for gestures).
- `Navigator.push(_ view:)` is not supported (the stack must remain route-backed / representable as a path).
- While UIKit is transitioning (animated push/pop, interactive swipe-back, iOS 18+ zoom dismiss), reconciliation is
  intentionally deferred and path mutations are coalesced until the transition completes. This avoids UIKit
  re-entrancy issues that can otherwise corrupt the navigation stack.

### External router example

```swift
@MainActor
final class AppRouter: ObservableObject {
    @Published var path = SUINavigationPath()

    func openThread(id: String) {
        // You can build heterogeneous paths here (multiple route types).
        try? path.append(route: ThreadRoute(id: id))
    }

    func goToRoot() {
        path.clear()
    }
}
```

Bind it into a shell:

```swift
@StateObject var router = AppRouter()

PathRestorableNavigationShell(
    id: "mainStack",
    idScope: .scene,
    path: $router.path,
    destinations: ThreadFeatureNavigation.destinations,
    root: { _ in InboxScreen() }
)
```

### Animation control

Path-driven pushes/pops animate by default (SwiftUI-like).

To disable animations for a specific path update (e.g. deep link), wrap it in a transaction:

```swift
var transaction = Transaction()
transaction.disablesAnimations = true
withTransaction(transaction) {
    router.path = newPath
}
```

## Zoom transitions (iOS 18+)

SUINavigationFusion supports the native iOS 18+ **zoom** navigation transition (the same system transition used by
Photos-style UIs). Under the hood, this is implemented via UIKit by configuring the destination view controller’s
`preferredTransition`.

### How to use

1) Mark the source view (e.g. a thumbnail) on the **current** screen:

```swift
Thumbnail(photo: photo)
    .suinavZoomSource(id: photo.id)
```

2) (Optional but recommended) mark the hero view on the **destination** screen:

```swift
Image(uiImage: photo.image)
    .resizable()
    .scaledToFit()
    .suinavZoomDestination(id: photo.id)
```

3) Request the transition when pushing:

```swift
navigator.push(
    route: PhotoRoute(id: photo.id),
    transition: .zoom(id: photo.id)
)
```

### Dynamic dismiss target (paging / changing content inside the detail screen)

UIKit calls the zoom transition’s `sourceViewProvider` closure both when pushing and when popping.
If your zoomed screen can change which “item” it represents *without leaving the screen* (for example, paging
between photos inside a single detail controller), the correct thumbnail to zoom back to can change over time.

To support this, apply `.suinavZoomDismissTo(...)` on the zoomed screen and update it whenever the current item changes:

```swift
struct PhotoDetail: View {
    @State var currentID: Photo.ID

    var body: some View {
        VStack {
            // The hero element for the currently displayed photo.
            PhotoHeroView(id: currentID)
                .suinavZoomDestination(id: currentID)

            // …
        }
        // Tell UIKit which thumbnail to zoom back to when dismissing.
        .suinavZoomDismissTo(id: currentID)
    }
}
```

If you need separate source/destination ids, use:

```swift
.suinavZoomDismissTo(sourceID: currentID, destinationID: currentID)
```

### Path-driven / external router control

In path-driven navigation, `navigator.push(route:transition:)` works the same way: it mutates the bound path and the
shell applies the requested transition when reconciling the UIKit stack.

If your router mutates the path directly, you can request a transition via a transaction (iOS 17+):

```swift
withSUINavigationTransition(.zoom(id: photo.id)) {
    router.path.append(route: PhotoRoute(id: photo.id))
}
```

### Default transitions via registry

You can provide a default transition while registering a destination. This is used when no explicit transition is
requested at the call site:

```swift
registry.register(PhotoRoute.self, defaultTransition: { route in
    .zoom(id: route.id)
}) { route in
    PhotoDetailScreen(id: route.id)
}
```

### Limitations and best practices

- Zoom transitions require iOS 18+ at runtime. On older OS versions, the library falls back to the standard push/pop.
- If multiple views register the same id at the same time, the last writer wins.
- If the source view is not available when popping back (e.g. scrolled offscreen), UIKit may fall back to a default
  animation.
- If you push a screen with `disableBackGesture: true`, SUINavigationFusion **always** disables zoom’s interactive
  dismiss gestures for that push, regardless of your transition policy. This keeps the library’s “no interactive back”
  contract consistent across edge-swipe back and zoom dismiss.

### Fluid transition invariants (for contributors)

iOS 18+ zoom transitions are continuously interactive and can be interrupted at any time. UIKit may run view controller
callbacks multiple times and may convert an interrupted push into a pop within the same run loop.

To keep navigation stable:

- Apple recommends not blocking pushes/pops just because a transition is running (UIKit handles continuous transitions).
  However, in SUINavigationFusion’s **path-driven** mode, UIKit mutations are triggered by SwiftUI reconciliation.
  We observed that attempting to reconcile (push/pop/setViewControllers) while UIKit is still transitioning can corrupt
  the navigation stack and break animations (especially for iOS 18+ zoom interactive dismiss). For correctness, the
  library **serializes** path-driven mutations by queueing them and applying once the transition finishes
  (`didShow` / transition-coordinator completion).
- Keep any temporary transition state one-shot and self-contained, and always clean it up in
  `UINavigationControllerDelegate.navigationController(_:didShow:animated:)` or a transition-coordinator completion.
- Do not publish SwiftUI state synchronously from `UIViewControllerRepresentable.updateUIViewController` / `View.body`.
  If UIKit state needs to flow back into SwiftUI, defer it to the next run loop tick.

### Interactive dismiss policy

UIKit’s zoom transitions can add interactive dismiss gestures (e.g. swipe-down/pinch) that are separate from
edge-swipe back. Use `SUINavigationZoomInteractiveDismissPolicy` to control whether those gestures are allowed to begin.

Common examples:

```swift
// Disable zoom interactive dismiss entirely.
transition: .zoom(id: photo.id, interactiveDismissPolicy: .disabled)

// Allow dismiss only when the gesture starts inside the hero element.
transition: .zoom(id: photo.id, interactiveDismissPolicy: .onlyFromDestinationAnchor())

// Compose multiple rules.
transition: .zoom(
  id: photo.id,
  interactiveDismissPolicy: .onlyFromDestinationAnchor()
    .and(.downwardSwipe(minimumVelocityY: 200))
)
```

### Alignment rect policy

The alignment rect controls *which area of the destination screen* the source view should zoom into.
For complex detail screens, providing an alignment rect often improves visual quality (reduces “ghosting” and jumps).

SUINavigationFusion exposes this via `SUINavigationZoomAlignmentRectPolicy`.

```swift
// Use the destination anchor (the view marked with `.suinavZoomDestination(id:)`).
transition: .zoom(id: photo.id, alignmentRectPolicy: .destinationAnchor())

// Inset the hero rect (in the destination view controller’s coordinate space).
transition: .zoom(
  id: photo.id,
  alignmentRectPolicy: .destinationAnchor(inset: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
)

// Full control (example: safe-area bounds).
transition: .zoom(id: photo.id, alignmentRectPolicy: .custom { $0.zoomedSafeAreaBounds })
```

### Dimming (color / blur behind the zoomed controller)

UIKit can apply a tint and/or a blur behind the zoomed controller during the zoom transition.

SUINavigationFusion exposes this via:
- `dimmingColor: Color?` (`nil` uses UIKit default)
- `dimmingVisualEffect: SUINavigationZoomDimmingVisualEffect?` (`nil` uses UIKit default, typically “no blur”)

```swift
transition: .zoom(
  id: photo.id,
  dimmingColor: .black.opacity(0.35),
  dimmingVisualEffect: .blur(style: .systemUltraThinMaterial)
)
```

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

## Top bar visibility

You can show/hide specific parts of the bar per screen:

```swift
// Hide the entire bar (and remove the safe-area inset).
.topNavigationBarVisibility(.hidden, for: .bar)

// Hide only specific regions.
.topNavigationBarVisibility(.hidden, for: .leading)
.topNavigationBarVisibility(.hidden, for: .principal)
.topNavigationBarVisibility(.hidden, for: .trailing)
.topNavigationBarVisibility(.hidden, for: .trailingPosition(.secondary))
```

## Back button
- Hidden automatically on the root screen.
- Per-screen control: `.topNavigationBarHidesBackButton(true)`
- Disable the interactive back swipe per push:

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

## Architecture

SUINavigationFusion is a SwiftUI-first façade over a UIKit `UINavigationController`:
- It hosts each SwiftUI screen inside a `UIHostingController` managed by a custom `NCUINavigationController`.
- It keeps the system `UINavigationBar` hidden and renders its own SwiftUI top bar instead.

### Core concepts

- **`Navigator` (imperative API)**
  - `Navigator` is injected as an `EnvironmentObject` into every hosted screen.
  - It performs push/pop on the underlying UIKit stack.
  - In path-driven mode (when a shell is created with `path:`), `Navigator` becomes a façade that mutates the bound
    `SUINavigationPath` instead of mutating UIKit directly.

- **Custom top bar (SwiftUI chrome)**
  - Screens describe their bar content using view modifiers (`.topNavigationBarTitle`, `.topNavigationBarLeading`, etc.).
  - Those modifiers write `PreferenceKey`s which are collected by a container modifier that renders the bar.
  - The bar is installed outside the screen subtree via `.safeAreaInset(edge: .top, ...)`, which is why per-screen
    tint overrides for bar items are intentionally not supported.

- **`TopNavigationBarConfiguration` (stack-wide styling)**
  - Shells inject a shared configuration store into the environment.
  - When `tintColor` is non-`nil`, the library applies it as a SwiftUI `.tint(...)` to the hosted view hierarchy and
    uses it for bar items.

- **Typed routing (registry)**
  - `NavigationDestinationRegistry` maps `{destinationKey, payloadType}` to “decode + build SwiftUI view”.
  - `TypedNavigationShell` installs the registry without persistence.
  - `PathRestorableNavigationShell` installs the registry and also enables persistence/restoration.
  - Feature modules can stay decoupled by exporting `NavigationDestinations` bundles.

- **Persistence / restoration**
  - The persisted form of the route-backed stack is `SUINavigationPath` (`schemaVersion` + `elements`).
  - The restoration engine rebuilds view controllers from `{key, payload}` via the registry.
  - The saved snapshot is kept authoritative by observing `UINavigationControllerDelegate.didShow` (covers swipe-back).

- **Path-driven navigation (external router-owned state)**
  - If a shell is created with `path:`, the UIKit stack is reconciled to match the bound `SUINavigationPath`.
  - Simple diffs (`push`/`pop`/`popToPrefix`) map to UIKit animated transitions; large diffs rebuild the stack.
  - Use SwiftUI transactions to control animation for path mutations:
    - default: animate
    - disable: `withTransaction(Transaction(disablesAnimations: true)) { ... }`

- **Zoom transitions (iOS 18+)**
  - For single-step pushes, the library can configure the destination view controller’s `preferredTransition` as a
    native `.zoom(...)` transition.
  - SwiftUI code provides UIKit anchor views via `.suinavZoomSource(id:)` / `.suinavZoomDestination(id:)`.
  - In path-driven mode, the transition request can be provided via `navigator.push(route:transition:)` or via a
    transaction using `withSUINavigationTransition(...)` (iOS 17+).


## Sample app

A compact sample showing titles, actions, push/pop, and scroll-aware background:
SUINavigationCore-Sample → https://github.com/ivalx1s/SUINavigationCore-Sample
