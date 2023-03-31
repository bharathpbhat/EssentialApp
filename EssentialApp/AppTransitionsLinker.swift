//
//  AppTransitionsLinker.swift
//  encee
//
//  Created by Bharath Bhat on 3/4/23.
//

import Foundation
import CoreData
import ScreenCaptureKit

struct TaggedWindow {
    let windowTitle: String
    let windowFrame: CGRect
    let bundleIdentifier: String
    let applicationName: String
    let timestamp: Date
}

class AppTransitionsLinker {
    
    enum StringMatchAggregationOp {
        case sum, avg
    }
   
    static func numWordsMatch(candidate: String, in text : String) -> Int {
        var numWordsMatched:Int =  0
        let words = candidate.split(separator: " ")
        for word in words {
            if text.contains(word) {
                numWordsMatched += 1
            }
        }
        return  numWordsMatched
    }
    
    static func stringMatchScoreInOcr(candidate: String, in frame: ScreenshotFrame, limitedTo window: CGRect, yExpScale: Double=1.0, aggregationOp: StringMatchAggregationOp = .avg) -> Double {
        let words = candidate.split(separator: " ")
        if words.count == 0 {
            return 0.0
        }
        
        var bestMatchForWords:[RecognizedText?] = words.map { _ in nil }
        
        for ocrText in frame.bestQualityOcrBoxes {
            if ocrText.box.intersects(window) {
                for (wordIndx,word) in words.enumerated() {
                    if ocrText.text.contains(word) {
                        if let prevMatch = bestMatchForWords[wordIndx] {
                            if ocrText.topLeftY > prevMatch.topLeftY {
                                bestMatchForWords[wordIndx] = ocrText
                            }
                        } else {
                            bestMatchForWords[wordIndx] = ocrText
                        }
                    }
                }
            }
        }
    
        var score = 0.0
        for bestMatchForWord in bestMatchForWords {
            if let bestMatch = bestMatchForWord {
                // Adjust to the window frame coordinates
                let adjustedTopY = max(0.0, min(1.0, (bestMatch.topLeftY - window.origin.y) / window.height))
                score += exp(-((1.0 - adjustedTopY) / yExpScale))
            }
        }
        
        if aggregationOp == .avg {
            return score / Double(words.count)
        } else {
            return score
        }
    }
    
    static func matchScore(window: TaggedWindow, frame: ScreenshotFrame) -> Double {
        
        let normalizedWindowFrame = CGRect(origin: CGPoint(x: window.windowFrame.origin.x / frame.width, y: window.windowFrame.origin.y / frame.height), size: CGSize(width: window.windowFrame.width / frame.width, height: window.windowFrame.height / frame.height))
        let titleMatchScore = stringMatchScoreInOcr(candidate: window.windowTitle, in: frame, limitedTo: normalizedWindowFrame, yExpScale: 1.0, aggregationOp: .avg)
        
        guard let frameCreatedAt = frame.createdAt else { return titleMatchScore }
        
        let timeScoreScale = 0.0 // 0.5
        let timeMatchScore = timeScoreScale * exp(-abs(frameCreatedAt.timeIntervalSince(window.timestamp)) / 60.0)
        
        let applicationNameWindow = CGRect(x: 0, y: 0.95, width: 0.25, height: 0.1) // topleft of the screen
        let applicationMatchScore = stringMatchScoreInOcr(candidate: window.applicationName, in: frame, limitedTo: applicationNameWindow, yExpScale: 1.0, aggregationOp: .sum)
        
        return titleMatchScore + timeMatchScore + applicationMatchScore
    }
    
    func run(context: NSManagedObjectContext, windowTransitions: Array<RunningAppWindowTransition>, processUptil: Date?=nil) async {
        await context.perform {
            let request = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
            
            if let processUptil = processUptil {
                request.predicate = NSPredicate(format: "parentSnippetContext == nil and taggedRunningApplication == nil and isCompacted = %@ and createdAt <= %@", NSNumber(value: true), processUptil as NSDate)
            } else {
                request.predicate = NSPredicate(format: "parentSnippetContext == nil and taggedRunningApplication == nil and isCompacted = %@", NSNumber(value: true))
            }
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let frames = (try? context.fetch(request)) ?? []
            
            if frames.isEmpty { return }
            
            let prevRunningAppRequest = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
            prevRunningAppRequest.predicate = NSPredicate(format: "parentSnippetContext == nil and taggedRunningApplication != nil and isCompacted = %@", NSNumber(value: true))
            prevRunningAppRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            prevRunningAppRequest.fetchLimit = 1
            let prevRunningAppFrame = (try? context.fetch(prevRunningAppRequest)) ?? []
            
            var prevWindow: TaggedWindow? = nil
            
            if prevRunningAppFrame.count > 0 {
                let runningApp = prevRunningAppFrame.first!.taggedRunningApplication
                if runningApp != nil {
                    prevWindow = TaggedWindow(windowTitle: runningApp!.windowTitle!, windowFrame: CGRect(x: runningApp!.frameX, y: runningApp!.frameY, width: runningApp!.frameWidth, height: runningApp!.frameHeight),
                                              bundleIdentifier: runningApp!.bundleIdentifier!,
                                              applicationName: runningApp!.applicationName!,
                                              timestamp: prevRunningAppFrame.first!.createdAt!)
                }
            }
            
            var nextWindowTransition: RunningAppWindowTransition? = nil
            
            var windowTransitionsIndx: Int = 0
            
            if prevWindow != nil {
                while windowTransitionsIndx < windowTransitions.count - 1 && windowTransitions[windowTransitionsIndx].timestamp < prevWindow!.timestamp{
                    windowTransitionsIndx += 1
                }
            }
            
            for frame in frames {
                while windowTransitionsIndx < windowTransitions.count - 1 && windowTransitions[windowTransitionsIndx +  1].timestamp < frame.createdAt!  {
                    windowTransitionsIndx += 1
                }
                nextWindowTransition = windowTransitionsIndx < windowTransitions.count ? windowTransitions[windowTransitionsIndx] : nil
                
                
                // Score previous
                var prevWindowScore:Double = -.infinity
                if prevWindow != nil {
                    prevWindowScore = AppTransitionsLinker.matchScore(window: prevWindow!, frame: frame)
                }
                
                var nextWindowScore: Double = -.infinity
                var nextWindow: TaggedWindow? = nil
                if let ee = nextWindowTransition {
                    for runningWindow in ee.runningAppWindows {
                        if runningWindow.title != nil && runningWindow.owningApplication != nil {
                            let candidateWindow = TaggedWindow(windowTitle: runningWindow.title!, windowFrame: runningWindow.frame, bundleIdentifier: runningWindow.owningApplication!.bundleIdentifier, applicationName: runningWindow.owningApplication!.applicationName, timestamp: ee.timestamp)
                            let windowScore = AppTransitionsLinker.matchScore(window: candidateWindow, frame: frame)
                            if windowScore > nextWindowScore {
                                nextWindowScore = windowScore
                                nextWindow = candidateWindow
                            }
                        }
                    }
                }
                
                let taggedRunningApplication = RunningApplication(context: context)
                if prevWindow != nil && prevWindowScore > nextWindowScore {
                    taggedRunningApplication.applicationName = prevWindow!.applicationName
                    taggedRunningApplication.bundleIdentifier = prevWindow!.bundleIdentifier
                    taggedRunningApplication.windowTitle = prevWindow!.windowTitle
                    taggedRunningApplication.frameX = prevWindow!.windowFrame.origin.x
                    taggedRunningApplication.frameY = prevWindow!.windowFrame.origin.y
                    taggedRunningApplication.frameWidth = prevWindow!.windowFrame.width
                    taggedRunningApplication.frameHeight = prevWindow!.windowFrame.height
                    
                } else if nextWindow != nil {
                    taggedRunningApplication.applicationName = nextWindow!.applicationName
                    taggedRunningApplication.bundleIdentifier = nextWindow!.bundleIdentifier
                    taggedRunningApplication.windowTitle = nextWindow!.windowTitle
                    taggedRunningApplication.frameX = nextWindow!.windowFrame.origin.x
                    taggedRunningApplication.frameY = nextWindow!.windowFrame.origin.y
                    taggedRunningApplication.frameWidth = nextWindow!.windowFrame.width
                    taggedRunningApplication.frameHeight = nextWindow!.windowFrame.height
                    prevWindow = nextWindow
                    windowTransitionsIndx += 1
                } else {
                    print("Both prev and next did not match. Something went wrong")
                    continue
                }
                frame.taggedRunningApplication = taggedRunningApplication
            }
            
            do {
                try context.save()
            } catch {
                print("App transitions linker save failed with \(error)")
            }
            
        }
    }
}

