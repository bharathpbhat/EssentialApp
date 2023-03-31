//
//  Snippet.swift
//  encee
//
//  Created by Bharath Bhat on 2/9/23.
//

import Foundation
import CoreData

struct SnippetUploadResponse: Codable {
    let uuid: String
}

extension Snippet {
    
    var text: String {
        get { text_ ?? "" }
        set { text_ = newValue }
    }
    
    func runAccurateOcr() {
        let textRecognizer = TextRecognizer()
        
        guard let snippetContext = self.snippetContext else { return }
        
        for screenshotFrame in snippetContext.screenshotFrames {
            let screenshotFrameId = screenshotFrame.objectID
            DispatchQueue.global(qos: .utility).async {
                Task {
                    let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                    await backgroundContext.perform {
                        do {
                            let backgroundContextFrame = try backgroundContext.existingObject(with: screenshotFrameId) as! ScreenshotFrame
                            backgroundContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
                            textRecognizer.performOCR(screenshotFrame: backgroundContextFrame, context: backgroundContext, level: .accurate)
                            try backgroundContext.save()
                        } catch { print("ERROR: \(error)") }
                    }
                }
            }
        }
    }
}

