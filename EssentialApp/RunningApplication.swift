//
//  RunningApplication.swift
//  encee
//
//  Created by Bharath Bhat on 3/5/23.
//

import Foundation

extension RunningApplication {

    var displayName: String {
        "\(self.applicationName!): \(self.windowTitle!)"
    }
}

