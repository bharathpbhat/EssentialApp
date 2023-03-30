//
//  EssentialAppApp.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 3/30/23.
//

import SwiftUI

@main
struct EssentialAppApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
