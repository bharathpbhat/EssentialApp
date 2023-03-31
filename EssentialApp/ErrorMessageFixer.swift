//
//  ErrorMessageFixer.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 4/23/23.
//

import Foundation
import CoreData

struct ErrorFixSuggestion: Codable {
    let error: String
    let fix: String
}

struct SuggestionsApiResponse: Codable {
    let response: [ErrorFixSuggestion]
}

struct SuggestionsApiRequest: Codable {
    let token: String
    let screen_text: String
    let uuid: String
}

class ErrorMessageFixer {
    
    let openai: OpenAIErrorMessageFixer
    
    init(){
        self.openai = OpenAIErrorMessageFixer()
    }
    
    func getTextInApp(frame: ScreenshotFrame) -> String {
        
        var text: String = ""
        for ocrBox in frame.bestQualityOcrBoxes {
            if let app = frame.taggedRunningApplication {
                let windowBounds = CGRect(
                    x: app.frameX / frame.width,
                    y: app.frameY / frame.height,
                    width: app.frameWidth / frame.width,
                    height: app.frameHeight / frame.height)
                if !ocrBox.box.intersects(windowBounds){
                    continue
                }
                
            }
            text += ocrBox.text
            text += "\n"
        }
        return text
    }
    
    func getErrorMessageFix(frame: ScreenshotFrame, context: NSManagedObjectContext) async {
        
        let screenText: String = getTextInApp(frame: frame)
        if let apiResponse = await self.openai.getFix(screenText: screenText) {
            await context.perform {
                for response in apiResponse.response {
                    let fixit = Fixit(context: context)
                    fixit.parentScreenshotFrame = frame
                    fixit.errorText = response.error
                    let suggestion = Suggestion(context: context)
                    suggestion.parentFixit = fixit
                    suggestion.text = response.fix
                }
            }
        }
    }
}
