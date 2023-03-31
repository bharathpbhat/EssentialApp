//
//  SettingsView.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 6/8/23.
//

import SwiftUI

struct SettingsView: View {
     
    @Binding var isPresented: Bool
    
    @State var openAiApiKey: String = ""
    @State var message: String? = nil
    
    func fetchKey(){
        let defaults = UserDefaults.standard
        self.openAiApiKey = defaults.string(forKey: Constants.openAIApiKey) ?? ""
    }
    
    func setKeyAndExit(){
        let defaults = UserDefaults.standard
        defaults.set(self.openAiApiKey, forKey: Constants.openAIApiKey)
        defaults.synchronize()
        self.isPresented = false
    }
   
    var body: some View {
        
        VStack() {
            
            Text("Settings")
            .padding(.horizontal)
            .padding(.vertical)
            .font(.title)
            Spacer()
            VStack(alignment: .leading){
                if let message = self.message {
                    Text(message)
                    .padding(.vertical)
                    .font(.title3)
                }
                
                Section(header: Text("Your OpenAI API Key")) {
                    HStack(spacing: 5){
                        TextField("Add openAI API Key here", text: $openAiApiKey)
                        Button("Add", action: setKeyAndExit).buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .frame(width: 900, height: 200, alignment: .bottomTrailing)
        .onAppear(perform: self.fetchKey)
    }
}
