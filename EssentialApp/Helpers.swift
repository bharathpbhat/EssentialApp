//
//  Helpers.swift
//  encee
//
//  Created by Bharath Bhat on 3/9/23.
//

import Foundation

enum ContextLevel: String {
    case last_15s, last_60s, last_screenshot, specific_frames, context_cleared_by_user
}

struct FrameCategory: Hashable {
    let displayName: String
    let beginIndx: Int // inclusive
    var endIndx: Int // exclusive
}

extension Data {
    
    /// Append string to Data
    ///
    /// Rather than littering my code with calls to `data(using: .utf8)` to convert `String` values to `Data`, this wraps it in a nice convenient little extension to Data. This defaults to converting using UTF-8.
    ///
    /// - parameter string:       The string to be added to the `Data`.
    
    mutating func append(_ string: String, using encoding: String.Encoding = .utf8) {
        if let data = string.data(using: encoding) {
            append(data)
        }
    }
}
