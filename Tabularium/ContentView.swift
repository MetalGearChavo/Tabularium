import SwiftUI

/// The root view. It decides what the user sees first: the onboarding wizard on
/// a fresh install, or the main app once setup is done.
struct ContentView: View {
    // `@AppStorage` reads/writes a `UserDefaults` value AND refreshes the View
    // when it changes. So the moment onboarding sets this flag true, this view
    // re-renders and swaps to `MainView`.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Every SwiftUI View describes its UI in `body`. `some View` means "some
    // specific view type I don't need to name".
    var body: some View {
        if hasCompletedOnboarding {
            MainView()
        } else {
            OnboardingView()
        }
    }
}

// `// MARK:` comments add labeled dividers to Xcode's jump bar — purely for navigation.
// MARK: - Main Navigation

/// The main window once onboarding is complete: a sidebar + a detail pane.
/// `private` means this type is only visible inside this file.
private struct MainView: View {
    // `@State` is view-local memory that survives re-renders. Here it's the
    // currently selected sidebar item. `AppScreen?` is optional (could be none).
    @State private var selection: AppScreen? = .dashboard

    var body: some View {
        // The Mac-standard two-column layout: a list on the left, content on the right.
        NavigationSplitView {
            // The sidebar. `selection: $selection` binds the highlighted row to our
            // state — the `$` passes a two-way binding so taps update `selection`.
            List(AppScreen.allCases, selection: $selection) { screen in
                Label(screen.rawValue, systemImage: screen.icon)
                    .tag(screen)   // ties this row to its `AppScreen` value for selection
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .navigationTitle("Tabularium")
            // Pin the LLM connection light to the very bottom of the sidebar.
            .safeAreaInset(edge: .bottom) {
                LLMStatusBadge()
            }
        } detail: {
            // The right-hand pane shows a different view depending on selection.
            switch selection {
            case .dashboard: DashboardView()
            case .settings:  SettingsView()
            case nil:        DashboardView()   // nothing selected → default to dashboard
            }
        }
    }
}

// MARK: - App Screens

/// The list of screens in the sidebar.
///
/// - `String` raw value: each case has a text value (its display name).
/// - `CaseIterable`: gives us `AppScreen.allCases` to loop over in the `List`.
/// - `Identifiable`: lets SwiftUI tell the rows apart.
enum AppScreen: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case settings = "Settings"

    var id: String { rawValue }   // use the name as the unique id

    /// SF Symbol icon name for each screen, shown in the sidebar label.
    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .settings:  return "gearshape.fill"
        }
    }
}

// `#Preview` renders this view live in Xcode's canvas without running the whole app.
#Preview {
    ContentView()
}
