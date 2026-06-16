//
//  TabulariumApp.swift
//  Tabularium
//
//  Created by Samuel  Ramírez  on 30/05/26.
//

import SwiftUI

// `@main` marks the app's entry point — execution starts here when it launches.
// There must be exactly one `@main` in the whole app.
@main
struct TabulariumApp: App {
    // An `App` describes the app's windows via its `body` (a `Scene`, not a `View`).
    var body: some Scene {
        // `WindowGroup` is a standard window. On Mac the user can open several.
        // Whatever View we put inside becomes the window's content — here the root
        // `ContentView`, which decides between onboarding and the main UI.
        WindowGroup {
            ContentView()
        }
    }
}
