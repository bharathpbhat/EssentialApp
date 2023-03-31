//
//  RecognizedText.swift
//  encee
//
//  Created by Bharath Bhat on 2/20/23.
//

import Foundation

extension RecognizedText {
    
    var text: String {
        get { text_ ?? "" }
        set { text_ = newValue }
    }
    
    var centerY: Double {
        0.5 * (topLeftY + bottomRightY)
    }
    
    var centerX: Double {
        0.5 * (topLeftX + bottomRightX)
    }
    
    var center: CGPoint {
        CGPoint(x: centerX, y: centerY)
    }
    
    var size: CGSize {
        CGSize(width: bottomRightX - topLeftX, height: topLeftY - bottomRightY)
    }
    
    var origin: CGPoint {
        CGPoint(x: topLeftX, y: bottomRightY)
    }
    
    var box: CGRect {
        CGRect(origin: origin, size: size)
    }
}
