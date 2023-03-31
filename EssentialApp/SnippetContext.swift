//  SnippetContext.swift
//  encee
//
//  Created by Bharath Bhat on 2/10/23.
//

import Foundation

extension SnippetContext {
    
    var screenshotFrames: Array<ScreenshotFrame> {
        get { return screenshotFrames_!.array as! Array<ScreenshotFrame> }
        set { screenshotFrames_ = NSOrderedSet(array: newValue) }
    }
    
    var lastScreenshotFrame: ScreenshotFrame? {
        screenshotFrames.last
    }
}
