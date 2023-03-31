//
//  OpenAIErrorMessageFixer.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 6/7/23.
//

import Foundation
import OpenAI

struct FixResponse: Codable {
    let response: [ErrorFixSuggestion]
}

class OpenAIErrorMessageFixer {
    
    private let openAI: OpenAI
    
    init(){
        let defaults = UserDefaults.standard
        let apiKey = defaults.string(forKey: Constants.openAIApiKey) ?? ""
        let configuration = OpenAI.Configuration(token: apiKey, timeoutInterval: 60.0)
        self.openAI = OpenAI(configuration: configuration)
    }
    
    func buildPrompt(screenText: String) -> String{
        return """
    Given all the text in a screenshot, please extract error messages from the text, and for each error message, suggest a fix, along with code samples to implement the fix. Your response should be in this format:
    error: first error text
    fix: fix for this error
    error: second error text
    fix: fix
    ...
    Input: \(screenText). Output:
    """
    }
    
    func parseResponse(response: String) -> SuggestionsApiResponse {
        var inErrorMode: Bool = false
        var errorLines: [String] = []
        var fixLines: [String] = []
        var responses: [ErrorFixSuggestion] = []
        for line in response.trimmingCharacters(in: .whitespacesAndNewlines) .split(whereSeparator: \.isNewline) {
            if line.lowercased().starts(with: "error:"){
                inErrorMode = true
                if fixLines.count > 0 {
                    let errorFixSuggestion = ErrorFixSuggestion(error: errorLines.joined(separator: "\n"), fix: fixLines.joined(separator: "\n"))
                    responses.append(errorFixSuggestion)
                    errorLines = []
                    fixLines = []
                }
                errorLines.append(String(line.replacing(/[Ee]rror\:/, with: "")))
            } else if line.lowercased().starts(with: "fix:"){
                inErrorMode = false
                fixLines.append(String(line.replacing(/[Ff]ix\:/, with: "")))
            } else {
                if inErrorMode {
                    errorLines.append(String(line))
                } else {
                    fixLines.append(String(line))
                }
            }
        }
        if fixLines.count > 0 {
            let errorFixSuggestion = ErrorFixSuggestion(error: errorLines.joined(separator: "\n"), fix: fixLines.joined(separator: "\n"))
            responses.append(errorFixSuggestion)
        }
        
        return SuggestionsApiResponse(response: responses)
    }
    
    func getFix(screenText: String) async -> SuggestionsApiResponse? {
        let prompt = buildPrompt(screenText: screenText)
        let query = CompletionsQuery(model: .textDavinci_003, prompt: prompt, temperature: 0.09, maxTokens: 1000)
        do {
            let result:CompletionsResult = try await self.openAI.completions(query: query)
            let responseText = result.choices[0].text
            return parseResponse(response: responseText)
        } catch {
            print("Error: \(error)")
            return nil
        }
    }
}
