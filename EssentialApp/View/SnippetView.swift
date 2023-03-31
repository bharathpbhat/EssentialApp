//
//  SnippetView.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 2/9/23.
//

import SwiftUI
import Combine

struct SnippetView: View {
    
    @Environment(\.openURL) var openURL
    
    @ObservedObject var snippetData: SnippetData
    @FetchRequest var frames: FetchedResults<ScreenshotFrame>
    
    @State var choosenFrameIndex = -1
    @State var timerStartFrameIndex = 0
    
    @State var tappedOcrBox: RecognizedText? = nil
    
    var derivedFrameIndex:Int {
        choosenFrameIndex >= 0 ? choosenFrameIndex : self.frames.count - 1
    }
    
    var lastFrameForSearchTerm: Int {
        for indx in (0..<self.snippetData.relevantOcrBoxes.count).reversed() {
            if self.snippetData.relevantOcrBoxes[indx].count > 0 {
                return indx
            }
        }
        return -1
    }
    
    @State var imageSwitcherTimer = Timer.publish(every: 1, on: .main, in: .common)
    @State var imageSwitcherTimerSubcription: Cancellable? = nil
    @State var isUploading:Bool = false
    
    init(snippetData: SnippetData){
        self.snippetData = snippetData
        let predicate = NSPredicate(format: "parentSnippetContext = %@", snippetData.snippet.snippetContext ?? "0")
        self._frames = FetchRequest(entity: ScreenshotFrame.entity(), sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)], predicate: predicate)
    }
    
    func setChosenFrameIndxFromLastFrameForSearchTerm(){
        self.choosenFrameIndex = lastFrameForSearchTerm
    }
    
    func cancelTimerIfExists() {
        self.imageSwitcherTimerSubcription?.cancel()
        self.imageSwitcherTimerSubcription = nil
    }
    
    var categoriesForFrames: Array<FrameCategory> {
        if self.frames.isEmpty { return [] }
        
        var categories: Array<FrameCategory> = []
        
        var currentCategory: FrameCategory? = nil
        for (frameIndx, frame) in self.frames.enumerated() {
            if let runningApplication = frame.taggedRunningApplication {
                if currentCategory == nil || currentCategory!.displayName != runningApplication.displayName {
                    if currentCategory != nil {
                        currentCategory?.endIndx = frameIndx
                        categories.append(currentCategory!)
                    }
                    let newCategory = FrameCategory(displayName: runningApplication.displayName, beginIndx: frameIndx, endIndx: frameIndx+1)
                    currentCategory = newCategory
                } else {
                    currentCategory?.endIndx = frameIndx + 1
                }
            } else {
                //print("Missing tagged application for frame indx: \(frameIndx)")
            }
        }
        if currentCategory != nil {
            categories.append(currentCategory!)
        }
        return categories
    }
    
    func getDisplayTextForContextLevel(_ contextLevel: ContextLevel) -> String? {
        switch contextLevel {
        case .last_15s:
            return "Context: last 15s"
        case .last_60s:
            return "Context: last 60s"
        case .last_screenshot:
            return "Context: last screenshot"
        case .specific_frames:
            return "Context: frames corresponding to search terms: "
        default:
            return nil
        }
    }
    
    func unsetTappedOcrBox() {
        self.tappedOcrBox = nil
    }
    
    func setTappedOcrBox(frameIndx: Int, loc: CGPoint) {
        let frame = self.frames[frameIndx]
        let ocrTexts = frame.bestQualityOcrBoxes
        
        let locYFlipped = CGPoint(x: loc.x, y: 1.0 - loc.y)
        for ocrBox in ocrTexts {
            if ocrBox.box.contains(locYFlipped) {
                tappedOcrBox = ocrBox
                break
            }
        }
    }

    var body: some View {
        VStack (alignment: .leading) {
            if !self.frames.isEmpty {
                if let imageData = self.frames[self.derivedFrameIndex].image {
                    if let image = NSImage(data: imageData) {
                        let imageHeightInContainer = image.size.height * 1200.0 / image.size.width
                        ZStack(alignment: .center) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(.horizontal)
                                .frame(width: 1200)
                                .onReceive(self.imageSwitcherTimer) {_ in
                                    self.choosenFrameIndex = min(self.choosenFrameIndex + 1,  self.frames.count - 1)
                                    if self.choosenFrameIndex == self.frames.count - 1 {
                                        cancelTimerIfExists()
                                    }
                                }
                                .onTapGesture(count: 2) { loc in
                                    self.choosenFrameIndex = self.derivedFrameIndex
                                    self.cancelTimerIfExists()
                                    let normalizedLoc = CGPoint(x: loc.x / 1200.0, y: loc.y / imageHeightInContainer)
                                    setTappedOcrBox(frameIndx: self.derivedFrameIndex, loc: normalizedLoc)
                                }.onTapGesture {
                                    unsetTappedOcrBox()
                                }
                            if let ocrBox = self.tappedOcrBox {
                                Text(ocrBox.text)
                                    .frame(width: 1.1 * ocrBox.size.width * 1200, height: 2.0 * ocrBox.size.height * imageHeightInContainer, alignment: .center)
                                    .padding(.vertical)
                                    .background(.white)
                                    .foregroundColor(.black)
                                    .offset(x: (ocrBox.center.x - 0.5) * 0.98 * 1200.0, y: (0.5 - ocrBox.center.y) * 0.98 * imageHeightInContainer)
                            }
                            if self.derivedFrameIndex < self.snippetData.relevantOcrBoxes.count {
                                ForEach(self.snippetData.relevantOcrBoxes[self.derivedFrameIndex], id: \.self){ocrBox in
                                    Rectangle().border(.red, width: 2)
                                        .foregroundColor(Color.white.opacity(0.0))
                                        .frame(width: 1.1 * ocrBox.size.width * 1200, height: 2.0 * ocrBox.size.height * imageHeightInContainer)
                                        .offset(x: (ocrBox.center.x - 0.5) * 0.98 * 1200.0, y: (0.5 - ocrBox.center.y) * 0.98 * imageHeightInContainer)
                                }
                            }
                        }
                        if let fixits = self.frames[self.derivedFrameIndex].fixits?.allObjects as? Array<Fixit> {
                            if (self.snippetData.snippet.snippetContext?.wasFixitRequested ?? false) || fixits.count > 0 {
                                VStack (alignment: .leading) {
                                    if fixits.count == 0 {
                                        
                                        Text("We could not identify issues to fix. Our system is still learning!")
                                            .foregroundColor(.black)
                                            .multilineTextAlignment(.leading)
                                            .padding()
                                            .frame(width: 1170, alignment: .leading)
                                            .background(Rectangle().fill(Color.gray))
                                        
                                        
                                    } else {
                                        ForEach(0..<fixits.count, id: \.self) { indx in
                                            let fixit:Fixit = fixits[indx]
                                            let suggestions = fixit.suggestions!.array as! Array<Suggestion>
                                            if let suggestion = suggestions.first {
                                                if let errorText = fixit.errorText {
                                                    Text(LocalizedStringKey(">> \(errorText)\n" + (suggestion.text ?? "") + "\n\n"))
                                                        .foregroundColor(.black)
                                                        .multilineTextAlignment(.leading)
                                                        .padding()
                                                        .frame(width: 1170, alignment: .leading)
                                                        .background(Rectangle().fill(Color.gray))
                                                    
                                                }
                                            }
                                        }
                                    }
                                }.padding()
                            }
                        }
                    }
                }
                VStack (alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<self.frames.count, id: \.self) { indx in
                            Rectangle()
                                .fill(indx == self.derivedFrameIndex ? Color.purple : Color.purple.opacity(0.5))
                                .frame(height: 10)
                                .onTapGesture(count: 2){
                                    self.choosenFrameIndex = indx
                                    self.cancelTimerIfExists()
                                }.onTapGesture {
                                    self.choosenFrameIndex = indx
                                    self.timerStartFrameIndex = indx
                                    self.imageSwitcherTimer = Timer.publish(every: 1, on: .main, in: .common)
                                    self.imageSwitcherTimerSubcription = self.imageSwitcherTimer.connect()
                                }
                        }
                    }.padding(.horizontal)
                    HStack(spacing: 2){
                        ForEach(self.categoriesForFrames, id: \.self){cat in
                            Text(cat.displayName).help(cat.displayName)
                                .frame(width: 1170.0 * Double(cat.endIndx - cat.beginIndx) / Double(self.frames.count), height: 20)
                                .background(Rectangle().fill(Color.gray))
                                .foregroundColor(.black)
                            
                        }
                    }.padding(.horizontal)
                    if let contextLevel = ContextLevel.init(rawValue: self.snippetData.snippet.snippetContext?.contextLevel ?? "") {
                        HStack(spacing: 5) {
                            if let contextLevelDisplayString = getDisplayTextForContextLevel(contextLevel) {
                                Text(contextLevelDisplayString)
                                    .font(Font.footnote)
                                    .foregroundColor(.gray)
                            }
                            if let frameSearchStrings = self.snippetData.snippet.snippetContext?.frameSearchStrings?.allObjects as? [FrameSearchString] {
                                ForEach(frameSearchStrings, id: \.self){ frameSearchString in
                                    Text(frameSearchString.query!)
                                        .font(Font.footnote)
                                        .foregroundColor(.gray)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal)
                    }
                }
            }
            
            Text(snippetData.snippet.text)
                .padding(.horizontal)
                .font(.title3)
                .frame(alignment: .leading)
            Divider().frame(height: 4).padding(.horizontal)
        }
        .padding(.vertical, 20)
        .onAppear(perform: {
            self.setChosenFrameIndxFromLastFrameForSearchTerm()
            if self.lastFrameForSearchTerm == -1 {
                self.imageSwitcherTimer = Timer.publish(every: 1, on: .main, in: .common)
                self.imageSwitcherTimerSubcription = self.imageSwitcherTimer.connect()
            }
        })
        .onChange(of: self.lastFrameForSearchTerm, perform: {_ in
            self.setChosenFrameIndxFromLastFrameForSearchTerm()
            if self.lastFrameForSearchTerm > -1 {
                self.cancelTimerIfExists()
            }
        })
        .textSelection(.enabled)
    }
}
