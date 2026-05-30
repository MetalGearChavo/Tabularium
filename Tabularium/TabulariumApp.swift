//
//  TabulariumApp.swift
//  Tabularium
//
//  Created by Samuel  Ramírez  on 30/05/26.
//

import SwiftUI
import CoreData

@main
struct TabulariumApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
