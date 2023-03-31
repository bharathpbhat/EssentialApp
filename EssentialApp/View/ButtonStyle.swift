//
//  ButtonStyle.swift
//  encee
//
//  Created by Bharath Bhat on 3/3/23.
//

import SwiftUI

struct ContextActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme

    private var isSelected: Bool = false
    
    init(isSelected: Bool) {
        self.isSelected = isSelected
    }
    
    func makeBody(configuration: Configuration) -> some View {
        if self.isSelected {
            if colorScheme == .dark {
                configuration.label
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                    .background(.blue)
                    .cornerRadius(10.0)
            } else  {
                configuration.label
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                    .background(Color(red: 204.0/255.0, green: 204.0/255.0, blue: 255.0/255.0))
                    .cornerRadius(10.0)
            }
        } else {
            if colorScheme == .dark {
                configuration.label
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                    .background(Color(red: 85.0 / 255.0, green: 85.0 / 255.0, blue: 85.0 / 255.0))
                    .cornerRadius(10.0)
            } else {
                configuration.label
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                    .background(.white)
                    .cornerRadius(10.0)

            }
        }
    }
}
