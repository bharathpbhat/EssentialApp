//
//  Constants.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 3/31/23.
//

import Foundation

struct Constants {
    static let onboardingCompleteKey = "onboardingComplete"
    static let openAIApiKey = "openAiApiKey"
    static let version = "0.0.1"
    static let frameRate:Int = 6  // 6 fps
    static let minFrameRate:Double = 1.0  // 1 fps
    static let lookbackWindow:TimeInterval = 300 // 5 min
    static let dirtyRectsFractionThreshold = 0.2 // Ignore if less than 20% screen changed
    #if DEBUG
    #else
    #endif
}
