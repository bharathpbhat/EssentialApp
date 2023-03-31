//
//  EssentialAppApp.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 3/30/23.
//

import SwiftUI
import Combine

@main
struct EssentialAppApp: App {
    let persistenceController = PersistenceController.shared
    let screenRecorder: ScreenRecorder

    
    init(){
        screenRecorder = ScreenRecorder(context: persistenceController.container.viewContext)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(screenRecorder)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .frame(width: 1200, height: 800)
        }
    }
}
