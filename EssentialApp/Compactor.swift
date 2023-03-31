//
//  Compactor.swift
//  encee
//
//  Created by Bharath Bhat on 2/23/23.
//

import Foundation
import CoreData

class Compactor {
    
    private let textRecognizer: TextRecognizer
    
    init(){
        self.textRecognizer = TextRecognizer()
    }
    
    func run(context: NSManagedObjectContext, processUptil: Date?=nil) async {
       // Runs every minute, picks the last 10 minutes of data, and discards the ones no longer needed
        await context.perform {
            let request = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
            if let processUptil = processUptil {
                request.predicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@ and createdAt <= %@", NSNumber(value: false), processUptil as NSDate)
            } else {
                request.predicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@", NSNumber(value: false))
            }
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let frames = (try? context.fetch(request)) ?? []
            
            if frames.isEmpty { return }
                        
            // Settin up the last frame for the UI
            frames[frames.count - 1].isCompacted = true
            
            // step through frames and decide which ones to keep.
            var i_indx:Int = frames.count - 2
            
            var leftWith:Int = 1
            while i_indx >= 0 {
                // if OCR transcript is the same, discard previous frame
                if frames[i_indx].accurateTranscriptHash != nil && frames[i_indx + 1].accurateTranscriptHash != nil {
                    if frames[i_indx].accurateTranscriptHash == frames[i_indx + 1].accurateTranscriptHash {
                        context.delete(frames[i_indx])
                    } else {
                        frames[i_indx].isCompacted = true
                        leftWith += 1
                    }
                } else {
                    if frames[i_indx].fastTranscriptHash == nil {
                        self.textRecognizer.performOCR(screenshotFrame: frames[i_indx], context: context, level: .fast)
                    }
                    if frames[i_indx + 1].fastTranscriptHash == nil {
                        self.textRecognizer.performOCR(screenshotFrame: frames[i_indx+1], context: context, level: .fast)
                    }
                    
                    if frames[i_indx].fastTranscriptHash == frames[i_indx + 1].fastTranscriptHash {
                        context.delete(frames[i_indx])
                    } else {
                        frames[i_indx].isCompacted = true
                        leftWith += 1
                    }
                }
                i_indx -= 1
            }
            
            do {
                context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
                try context.save()
                context.mergePolicy = NSErrorMergePolicy
            } catch {
                print("compaction save failed: \(error)")
            }
            
        }
    }
}

