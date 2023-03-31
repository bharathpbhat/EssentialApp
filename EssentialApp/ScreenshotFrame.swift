//
//  ScreenshotFrame.swift
//  encee
//
//  Created by Bharath Bhat on 2/10/23.
//

import Foundation
import CoreImage
import CoreData

extension ScreenshotFrame {
    
    var isAccurateTranscriptAvailable: Bool {
        self.accurateTranscriptHash != nil
    }
    
    var bestQualityOcrBoxes: Array<RecognizedText> {
        self.isAccurateTranscriptAvailable ? ocrBoxesOfType("accurate") : ocrBoxesOfType("fast")
    }
    
    func ocrBoxesOfType(_ modelType: String) -> Array<RecognizedText> {
        guard let context = self.managedObjectContext else { return [] }
        let ocrReq = NSFetchRequest<RecognizedText>(entityName: "RecognizedText")
        ocrReq.predicate = NSPredicate(format: "modelType == %@ and parentScreenshotFrame == %@ and isCompact == %@", modelType, self, NSNumber(value: false))
        ocrReq.sortDescriptors = [NSSortDescriptor(key: "orderIndx", ascending: true)]
        return (try? context.fetch(ocrReq)) ?? []
    }
}
