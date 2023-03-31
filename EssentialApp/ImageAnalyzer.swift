//
//  ImageAnalyzer.swift
//  encee
//
//  Created by Bharath Bhat on 2/10/23.
//

import Foundation
import Vision
import CryptoKit
import CoreData

class ImageAnalyzer {
    
}

class TextRecognizer {
    
    init() {
        
    }
    
    func performOCR(screenshotFrame: ScreenshotFrame, context: NSManagedObjectContext, level: VNRequestTextRecognitionLevel = .accurate) {
        
        if (level == .fast && screenshotFrame.fastTranscript != nil) || (level == .accurate && screenshotFrame.accurateTranscript != nil) {
            // nothing to do, transcript exists already.
            return
        }
        
        if let image = screenshotFrame.image {
            let textRecognitionRequest = VNRecognizeTextRequest(completionHandler: self.createTextHandler(context: context, screenshotFrame: screenshotFrame, level: level))
            textRecognitionRequest.recognitionLevel = level
            textRecognitionRequest.usesLanguageCorrection = true
            textRecognitionRequest.revision = 2
            
            let requestHandler = VNImageRequestHandler(data: image)
            do {
                try requestHandler.perform([textRecognitionRequest])
            } catch _ {print("OCR failed")}
        }
    }
     
    func createTextHandler(context: NSManagedObjectContext, screenshotFrame: ScreenshotFrame, level: VNRequestTextRecognitionLevel) -> ((VNRequest, Error?) -> Void) {
        func recognizeTextHandler(request: VNRequest, error: Error?) {
            if let results = request.results {
                let textResults = results as! [VNRecognizedTextObservation]
                var transcript: String = ""
                var orderIndx:Int64 = 0
                for observation in textResults {
                    let recognizedText = RecognizedText(context: context)
                    recognizedText.modelType = level == .accurate ? "accurate" : "fast"
                    recognizedText.topLeftX = observation.topLeft.x
                    recognizedText.topLeftY = observation.topLeft.y
                    recognizedText.bottomRightX = observation.bottomRight.x
                    recognizedText.bottomRightY = observation.bottomRight.y
                    recognizedText.isCompact = false
                    recognizedText.parentScreenshotFrame = screenshotFrame
                    
                    recognizedText.orderIndx = orderIndx
                    orderIndx += 1
                    
                    // Build plain text transcript
                    let text = observation.topCandidates(1)[0].string
                    transcript.append(text)
                    transcript.append("\n")
                    
                    recognizedText.text = text
                }
                if level == .accurate {
                    screenshotFrame.accurateTranscript = transcript
                    screenshotFrame.accurateTranscriptHash = SHA256.hash(data: Data(transcript.utf8)).description
                } else {
                    screenshotFrame.fastTranscript = transcript
                    screenshotFrame.fastTranscriptHash = SHA256.hash(data: Data(transcript.utf8)).description
                }
            }
        }
        return recognizeTextHandler
    }
}

