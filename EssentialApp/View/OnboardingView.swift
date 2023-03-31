//
//  OnboardingView.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 6/7/23.
//

import SwiftUI

struct OnboardingView: View {
    
    @Environment(\.openURL) var openURL
    
    private var screenRecorder: ScreenRecorder;
   
    init(isPresented: Binding<Bool>, screenRecorder: ScreenRecorder){
        
        self._isPresented = isPresented
        self.screenRecorder = screenRecorder
    }
    
    static let welcomeMessage:String = """
        
        Hi there! Thanks for trying Essential - a co-pilot for your screen. Essential is a tool built for developers. It is like having a second set of eyes on your screen to help you be more productive. Essential keeps track of the last 5 minutes of your screen, and uses Computer Vision and LLMs to help you:
        
        FIXIT
                
        Whenever you see an error message on screen, \u{2318}-tab over to this app, and hit Fixit to see a code fix that works in your context.

        REMEMBER
        
        Whenever you read/do something you feel would be useful for later reference, \u{2318}-tab over to this app to save all that rich screen context with a note. You can search over your notes and all screen text, and optionally, choose to publish your note to share it with others.
                
        """

    @Binding var isPresented: Bool
     
    func requestPermissions() {
        Task {
            if await screenRecorder.canRecord {
                screenRecorder.setPermissionsBit(true)
                DispatchQueue.main.async {
                    self.isPresented = false
                }
            } else {
                screenRecorder.setPermissionsBit(false)
            }
        }
    }
    
    var frameHeight: CGFloat {
        return 400
    }
    
    var body: some View {
        VStack() {
            Text(OnboardingView.welcomeMessage)
                .padding(.horizontal)
                .padding(.vertical)
                .font(.title3)
            
            HStack(spacing: 25){
                Button("Visit Website") {
                    if let url = URL(string: "https://getessential.app") {
                        openURL(url)
                    }
                }
                Button("Allow Screen Recording Permissions") {
                    let defaults = UserDefaults.standard
                    defaults.set(true, forKey: Constants.onboardingCompleteKey)
                    defaults.synchronize()
                    self.requestPermissions()
                }.buttonStyle(.borderedProminent)
            }
            
        }.padding()
            .frame(width: 900, height: self.frameHeight, alignment: .bottomLeading)
    }
}
