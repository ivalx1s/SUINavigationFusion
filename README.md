# SUINavigationCore

A SwiftUI-first navigation core with a customizable top bar and a thin UIKit bridge.
It hides UINavigationBar, drives your own top bar via environment, and exposes a tiny Navigator API for push/pop.

Requirements
	•	iOS 15+
	•	Swift 5.10+ (supports Swift 6 strict concurrency)

## Installation

Add SUINavigationCore to your target via Xcode → Package Dependencies (or whatever your setup is) and link the product SUINavigationCore.

## Quick start

```swift
import SwiftUI
import SUINavigationCore

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationShell(configuration: .defaultMaterial) { navigator in
                InboxScreen()
                    .topNavigationBarTitle("Inbox")
                    .topNavigationBarSubtitle { Text("All messages • 127") }
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
    tintColor: .accentColor,                     // affects back icon & bar items
    backButtonIcon: .init(name: "custom_back", bundle: .main) // optional, defaults to chevron
)
```

Apply it when creating the shell:

```swift
NavigationShell(configuration: config) { navigator in
    RootView()
}
```

## Title & subtitle

Use plain strings: .topNavigationBarTitle("Title"), .topNavigationBarSubtitle("Subtitle") or provide fully styled Text (overrides config fonts/colors):

```swift
.topNavigationBarTitle { Text("Title").kerning(0.5) }
.topNavigationBarSubtitle { Text("Details").foregroundStyle(.secondary) }
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
