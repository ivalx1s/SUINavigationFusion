```swift
import SwiftUI
import SUINavigationFusion

@main
struct NavigationFusionSampleApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationShell(configuration: demoTopBarConfig) { navigator in
                RootScreen()
                // Root title/subtitle + actions
                    .topNavigationBarTitle("Inbox")
                    .topNavigationBarSubtitle { Text("All messages • 127") }
                    .topNavigationBarLeading {
                        Button(action: { }) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .padding(.leading, 4)
                        }
                    }
                    .topNavigationBarTrailing(position: .secondary) {
                        Button { /* search */ } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                    }
                    .topNavigationBarTrailingPrimary {
                        Button {
                            navigator.push(ComposeScreen(), disableBackGesture: true)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
            }
        }
    }
}
```

full smaple – [https://github.com/ivalx1s/SUINavigationCore-Sample](https://github.com/ivalx1s/SUINavigationCore-Sample)
