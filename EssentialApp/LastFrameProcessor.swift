//
//  LastFrameProcessor.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 4/29/23.
//

import Foundation
import CoreData

class LastFrameProcessor {
    static func run(context: NSManagedObjectContext, windowTransitions: Array<RunningAppWindowTransition>){
        let request = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        request.predicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@", NSNumber(value: false))
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        let frames = (try? context.fetch(request)) ?? []
        
        if frames.isEmpty { return }
                    
        // Settin up the last frame for the UI
        frames[0].isCompacted = true
        
        guard let lastWindowTransiion = windowTransitions.last else { return }
        guard let lastAppWindow = lastWindowTransiion.runningAppWindows.first else { return }
        guard let owningApplication = lastAppWindow.owningApplication else { return }
        
        let taggedRunningApplication = RunningApplication(context: context)
        taggedRunningApplication.applicationName = owningApplication.applicationName
        taggedRunningApplication.bundleIdentifier = owningApplication.bundleIdentifier
        taggedRunningApplication.windowTitle = lastAppWindow.title 
        taggedRunningApplication.frameX = lastAppWindow.frame.origin.x
        taggedRunningApplication.frameY = lastAppWindow.frame.origin.y
        taggedRunningApplication.frameWidth = lastAppWindow.frame.width
        taggedRunningApplication.frameHeight = lastAppWindow.frame.height
        
        frames[0].taggedRunningApplication = taggedRunningApplication
        
        TextRecognizer().performOCR(screenshotFrame: frames[0], context: context, level: .accurate)
        
        do {
            try context.save()
        } catch {
            print("Single frame linker save failed with \(error)")
        }
    }
}
