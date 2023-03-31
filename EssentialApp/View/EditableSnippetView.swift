//
//  EditableSnippetView.swift
//  encee
//
//  Created by Bharath Bhat on 2/23/23.
//

import SwiftUI
import Combine

enum Field {
    case frameSearch, noteField
}

struct ViewData {
    let frames: Array<ScreenshotFrame>
    let images:  Array<NSImage>
    let categories: Array<FrameCategory>
    let ocrBoxes: Array<Array<RecognizedText>>
}

struct EditableSnippetView: View {
    
    @ObservedObject var screenRecorder: ScreenRecorder
    @FetchRequest var frames: FetchedResults<ScreenshotFrame>
    @FetchRequest var unprocessedFrames: FetchedResults<ScreenshotFrame>
    
    @State var editableNoteText = ""
    
    @State var choosenFrameIndex = -1
    @State var timerStartFrameIndex = 0
    
    @State var currentContextLevel:ContextLevel = .last_screenshot
    
    @FocusState private var focusedField: Field?
    @State var frameSearchString: String = ""
    @State var addedFrameSearchStrings: Array<String> = []
    @State var addedFramesFromSearch: Array<ScreenshotFrame> = []
    
    @State var frameSearchResults: Array<ScreenshotFrame> = []
    @State var frameSearchOcrBoxes: Array<Array<RecognizedText>> = []
    @State var framesForLast15: Array<ScreenshotFrame> = []
    @State var framesForLast60: Array<ScreenshotFrame> = []
    @State var framesForLastScreenshot: Array<ScreenshotFrame> = []
    
    @State var keepCategory:  FrameCategory? = nil
    @State var removedCategories: Array<FrameCategory> = []
    
    @State var currentViewData: ViewData = ViewData(frames: [], images: [], categories: [], ocrBoxes: [])
    
    @State var presentApiKeySheet:Bool = false
    
    @Environment(\.managedObjectContext) var managedObjectContext
    
    var derivedFrameIndex:Int {
        min(self.currentViewData.frames.count - 1, choosenFrameIndex >= 0 ? choosenFrameIndex : 0)
    }
    
    var lastScreenshotTime: Date? {
        self.frames.first?.createdAt
    }
    
    var firstScreenshotTime: Date? {
        self.frames.last?.createdAt
    }
    
    var contextWindowTimeInterval: TimeInterval? {
        if lastScreenshotTime != nil && firstScreenshotTime != nil {
            return lastScreenshotTime?.timeIntervalSince(firstScreenshotTime!)
        } else {
            return nil
        }
    }
    
    func isContextAvailable(for cutoffTime: Double) -> Bool {
        return (contextWindowTimeInterval != nil && contextWindowTimeInterval! >= cutoffTime) || self.olderUnprocessedFrames.count == 0
    }
    
    var placeholderText: String? {
        if currentContextLevel == .specific_frames {
            if self.currentViewData.frames.isEmpty {
                if self.frameSearchString.isEmpty {
                    return "Frames that match your search will appear here."
                } else {
                    return "No frames match your search."
                }
            }
        } else if currentContextLevel == .context_cleared_by_user {
            return "Screen context available. Select one of the options below to include."
        } else {
            if !self.screenRecorder.lastFrameProcessingDone {
                return "Loading context..."
            }
        }
        return nil
    }
    
    var olderUnprocessedFrames: Array<ScreenshotFrame> {
        if self.frames.count == 0 {
            return Array<ScreenshotFrame>(self.unprocessedFrames)
        }
        
        let ret = self.unprocessedFrames.filter { frame in
            frame.createdAt != nil && frame.createdAt! <= self.frames.first!.createdAt!
        }
        return ret
    }
    
    @State var imageSwitcherTimer = Timer.publish(every: 1, on: .main, in: .common)
    @State var imageSwitcherTimerSubcription: Cancellable? = nil
    
    @State var refreshCategoriesTimer = Timer.publish(every: 0.5, on: .main, in: .common)
    @State var refreshCategoriesTimerSubscription: Cancellable? = nil
    
    init(screenRecorder: ScreenRecorder){
        self.screenRecorder = screenRecorder
        let request = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        request.predicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@", NSNumber(value: true))
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 60 * 6 // 6 fps, max context of 60s
        self._frames = FetchRequest(fetchRequest: request)
        
        // Unprocessed
        let unprocessedPredicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@", NSNumber(value: false))
        self._unprocessedFrames = FetchRequest(entity: ScreenshotFrame.entity(), sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)], predicate: unprocessedPredicate)
    }
    
    func addFrameSearchResults() -> Void {
        addedFrameSearchStrings.append(frameSearchString)
        frameSearchString = ""
        addedFramesFromSearch = Array<ScreenshotFrame>(Set<ScreenshotFrame>(self.frameSearchResults + addedFramesFromSearch)).sorted { $0.createdAt! <= $1.createdAt! }
    }
    
    func setTimer() -> Void {
        self.imageSwitcherTimer = Timer.publish(every: 1, on: .main, in: .common)
        self.imageSwitcherTimerSubcription = self.imageSwitcherTimer.connect()
    }
    
    func setCategoriesRefreshTimer() -> Void {
        self.refreshCategoriesTimer = Timer.publish(every: 0.5, on: .main, in: .common)
        self.refreshCategoriesTimerSubscription = self.refreshCategoriesTimer.connect()
    }
    
    func setContextLevel(_ contextLevel: ContextLevel){
        self.currentContextLevel = contextLevel
        cancelTimerIfExists()
        setViewData()
        choosenFrameIndex = -1
        timerStartFrameIndex = 0
        if self.currentContextLevel != .specific_frames {
            self.frameSearchString = ""
        }
        setTimer()
    }
    
    var availableContextLevelActions: Array<ContextLevel> {
        var availableLevels: Array<ContextLevel> = []
        
        if self.frames.count > 0 {
            availableLevels = [.specific_frames]
            if self.currentContextLevel != .context_cleared_by_user {
                availableLevels.append(.context_cleared_by_user)
            }
            
            if self.addedFrameSearchStrings.count == 0 && self.keepCategory == nil {
                availableLevels.append(.last_screenshot)
                // disable options if the user has added a search term
                if self.isContextAvailable(for: 15.0) {
                    availableLevels.append(.last_15s)
                    
                    if self.isContextAvailable(for: 60.0) && self.framesForContext(.last_60s).count > self.framesForContext(.last_15s).count {
                        availableLevels.append(.last_60s)
                    }
                }
            }
        }
        return availableLevels
    }
    
    func resetStateVars(){
        editableNoteText = ""
        addedFramesFromSearch = []
        addedFrameSearchStrings = []
        frameSearchResults = []
        framesForLast15 = []
        framesForLast60 = []
        framesForLastScreenshot = []
        focusedField = .noteField
        setContextLevel(.last_screenshot)
    }

    func cancelTimerIfExists() {
        self.imageSwitcherTimerSubcription?.cancel()
        self.imageSwitcherTimerSubcription = nil
    }
    
    func cancelRefreshCategoriesTimerIfExists() {
        self.refreshCategoriesTimerSubscription?.cancel()
        self.refreshCategoriesTimerSubscription = nil
    }
    
    func cutoffTimeForContext(_ contextLevel: ContextLevel) -> Double {
        switch contextLevel {
        case .context_cleared_by_user:
            return -1.0
        case .last_60s:
            return 60.0
        case .last_15s:
            return 15.0
        case .last_screenshot:
            return 0.0
        case .specific_frames:
            return 0.0 // TODO: this is not consistent.
        }
    }
    
    func setFramesForContexts() {
        if self.frames.isEmpty {
            self.framesForLast15 = []
            self.framesForLast60 = []
            self.framesForLastScreenshot = []
            return
        }
        
        // last 15s
        guard let cutoffTimeLast15 = lastScreenshotTime?.addingTimeInterval(-cutoffTimeForContext(.last_15s)) else { return }
        self.framesForLast15 = self.frames.filter { frame in
            frame.createdAt != nil && frame.createdAt! >= cutoffTimeLast15
        }.reversed()
        
        // last 60s
        guard let cutoffTimeLast60 = lastScreenshotTime?.addingTimeInterval(-cutoffTimeForContext(.last_60s)) else { return }
        self.framesForLast60 = self.frames.filter { frame in
            frame.createdAt != nil && frame.createdAt! >= cutoffTimeLast60
        }.reversed()
        
        // last screenshot
        guard let cutoffTimeLast = lastScreenshotTime?.addingTimeInterval(-cutoffTimeForContext(.last_screenshot)) else {return }
        self.framesForLastScreenshot = self.frames.filter { frame in
            frame.createdAt != nil && frame.createdAt! >= cutoffTimeLast
        }.reversed()
    }
    
    func framesForContext(_ contextLevel: ContextLevel) -> Array<ScreenshotFrame> {
        switch contextLevel {
        case .specific_frames:
            return self.frameSearchResults
        case .last_15s:
            return self.framesForLast15
        case .last_60s:
            return self.framesForLast60
        case .last_screenshot:
            return self.framesForLastScreenshot
        default:
            return []
        }
    }
    
    func runFrameSearchQuery() {
        let request = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        request.predicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@ and fastTranscript contains[c] %@", NSNumber(value: true), self.frameSearchString)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        self.frameSearchResults = (try? self.managedObjectContext.fetch(request)) ?? []
        
        var relevantOcrBoxes: Array<Array<RecognizedText>> = []
        for frame in self.frameSearchResults {
            let ocrReq = NSFetchRequest<RecognizedText>(entityName: "RecognizedText")
            ocrReq.predicate = NSPredicate(format: "parentScreenshotFrame == %@ and text_ contains[c] %@", frame, self.frameSearchString)
            relevantOcrBoxes.append((try? self.managedObjectContext.fetch(ocrReq)) ?? [])
        }
        self.frameSearchOcrBoxes = relevantOcrBoxes
        setViewData()
    }
    
    private func mergeOldAndNewSearchResults() -> Array<ScreenshotFrame> {
        // They are both sorted arrays
        let newFrames = framesForContext(self.currentContextLevel)
        if newFrames.count == 0 { return addedFramesFromSearch }
        if addedFramesFromSearch.count == 0 { return newFrames }
        
        var newIndx:Int = 0
        var oldIndx:Int = 0
        var ret:Array<ScreenshotFrame> = []
        while newIndx < newFrames.count && oldIndx < addedFramesFromSearch.count {
            if newFrames[newIndx].createdAt! <= addedFramesFromSearch[oldIndx].createdAt! {
                ret.append(newFrames[newIndx])
                newIndx += 1
            } else {
                ret.append(addedFramesFromSearch[oldIndx])
                oldIndx += 1
            }
        }
        
        while newIndx < newFrames.count {
            ret.append(newFrames[newIndx])
            newIndx += 1
        }
        
        while oldIndx < addedFramesFromSearch.count {
            ret.append(addedFramesFromSearch[oldIndx])
            oldIndx += 1
        }
        
        return ret
    }
    
    func setViewData() {
        let frames  = getFramesForView()
        let categories = getCategoriesForFrames(frames)
        let images = getImagesForFrames(frames)
        let ocrBoxes =  getOcrBoxesForView()
        
        if images.count == frames.count {
            self.currentViewData = ViewData(
                frames: frames, images: images, categories: categories, ocrBoxes: ocrBoxes)
        } else {
            print("Frame(\(frames.count)) count and images(\(images.count)) count does not match")
        }
    }
    
    func getOcrBoxesForView() -> Array<Array<RecognizedText>> {
        self.currentContextLevel == .specific_frames ? self.frameSearchOcrBoxes : []
    }
    
    func getImagesForFrames(_ frames: Array<ScreenshotFrame>) -> Array<NSImage> {
        var ret: Array<NSImage> = []
        for frame in frames {
            if let imageData = frame.image {
                if let image = NSImage(data: imageData) {
                    ret.append(image)
                }
            }
        }
        return ret
    }
    
    func getFramesForView() -> Array<ScreenshotFrame> {
        var ret: Array<ScreenshotFrame>
        if self.addedFramesFromSearch.count > 0 {
            ret = mergeOldAndNewSearchResults()
        } else {
            ret = framesForContext(self.currentContextLevel)
        }
        
        if let cat = keepCategory {
            return ret.filter { $0.taggedRunningApplication?.displayName == cat.displayName }
        }
        
        if removedCategories.count > 0 {
            return ret.filter { frame in
                for cat in removedCategories {
                    if cat.displayName == frame.taggedRunningApplication?.displayName {
                        return false
                    }
                }
                return true
            }
        }
        return ret
    }
    
    func getCategoriesForFrames(_ frames: Array<ScreenshotFrame>) -> Array<FrameCategory> {
        if frames.isEmpty { return [] }
        
        var categories: Array<FrameCategory> = []
        
        var currentCategory: FrameCategory? = nil
        var needsRefresh: Bool = false
        for (frameIndx, frame) in frames.enumerated() {
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
                needsRefresh = true
            }
        }
        if currentCategory != nil {
            categories.append(currentCategory!)
        }
        if needsRefresh {
            self.setCategoriesRefreshTimer()
        } else {
            self.cancelRefreshCategoriesTimerIfExists()
        }
        return categories
    }
    
    func removeSection(_ category: FrameCategory){
        removedCategories.append(category)
        setViewData()
    }
    
    func keepSection(_ category: FrameCategory){
        keepCategory = category
        setViewData()
    }
    
    func submitNote() {
        if (editableNoteText.count > 0 || self.currentViewData.frames.count > 0){
            screenRecorder.saveSnippet(editableNoteText: self.editableNoteText,  frameIDs: self.currentViewData.frames.map { $0.uuid! }, contextLevel: self.currentContextLevel, frameSearchStrings: self.addedFrameSearchStrings + (self.frameSearchString.count > 0 ? [self.frameSearchString] : []))
            self.resetStateVars()
        }
    }
    
    func runFixit(){
        if self.screenRecorder.suggestionState == .not_asked {
            if let lastFrame = self.currentViewData.frames.last {
                self.screenRecorder.getErrorMessageFix(
                    inputData: FixitInputData(frames: [lastFrame],
                    frameSearchStrings: self.addedFrameSearchStrings + (self.frameSearchString.count > 0 ? [self.frameSearchString] : []),
                        contextLevel: self.currentContextLevel))
            }
        }
    }
    
    var body: some View {
        VStack (alignment: .leading) {
            if self.placeholderText != nil {
                if !self.unprocessedFrames.isEmpty {
                    if let imageData = self.unprocessedFrames[0].image {
                        if let image = NSImage(data: imageData) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(.horizontal)
                                .frame(width: 1200)
                                .redacted(reason: .placeholder)
                                .overlay(Text(self.placeholderText!).font(.title3))
                        }
                    }
                } else if !self.frames.isEmpty {
                     if let imageData = self.frames[0].image {
                        if let image = NSImage(data: imageData) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(.horizontal)
                                .frame(width: 1200)
                                .redacted(reason: .placeholder)
                                .overlay(Text(self.placeholderText!).font(.title3))
                        }
                    }
                } else {
                     Text(self.placeholderText!)
                     .padding(.horizontal)
                     .padding(.vertical)
                     .frame(height:  screenRecorder.contentSize.height)
                }
                VStack (alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<1, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.purple.opacity(0.1))
                                .frame(height: 10)
                                .redacted(reason: .placeholder)
                        }
                    }
                    .padding(.horizontal)
                    HStack(spacing: 2){
                        ForEach(0..<1, id: \.self){_ in
                            Text("")
                                .frame(width: 1170.0, height: 20)
                                .background(Rectangle().fill(Color.gray.opacity(0.1)))
                                .foregroundColor(.black)
                                .redacted(reason: .placeholder)
                            
                        }
                    }.padding(.horizontal)
                }
            } else {
                if !self.currentViewData.frames.isEmpty {
                    ZStack(alignment: .center) {
                        Image(nsImage: self.currentViewData.images[self.derivedFrameIndex])
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal)
                            .frame(width: 1200)
                            .onReceive(self.imageSwitcherTimer) {_ in
                                self.choosenFrameIndex = min(self.choosenFrameIndex + 1, self.currentViewData.frames.count -  1)
                                if self.choosenFrameIndex == self.currentViewData.frames.count - 1 {
                                    cancelTimerIfExists()
                                }
                            }
                        if self.derivedFrameIndex < self.currentViewData.ocrBoxes.count {
                            let imageHeightInContainer = self.currentViewData.images[self.derivedFrameIndex].size.height * 1200.0 / self.currentViewData.images[self.derivedFrameIndex].size.width
                            ForEach(self.currentViewData.ocrBoxes[self.derivedFrameIndex], id: \.self){ocrBox in
                                Rectangle().border(.red, width: 2)
                                    .foregroundColor(Color.white.opacity(0.0))
                                    .frame(width: ocrBox.size.width * 1200, height: 1.2 * ocrBox.size.height * imageHeightInContainer)
                                    .offset(x: (ocrBox.center.x - 0.5) * 0.98 * 1200.0, y: (0.5 - ocrBox.center.y) * 0.98 * imageHeightInContainer)
                            }
                        }
                    }
                    VStack (alignment: .leading) {
                        HStack(spacing: 2) {
                            ForEach(0..<self.currentViewData.frames.count, id: \.self) { indx in
                                Rectangle()
                                    .fill(indx == self.derivedFrameIndex ? Color.purple : Color.purple.opacity(0.5))
                                    .frame(height: 10)
                                    .onTapGesture(count: 2){
                                        self.choosenFrameIndex = indx
                                        self.cancelTimerIfExists()
                                    }.onTapGesture {
                                        self.choosenFrameIndex = indx
                                        self.timerStartFrameIndex = indx
                                        setTimer()
                                    }
                            }
                        }
                        .padding(.horizontal)
                        HStack(spacing: 2){
                            ForEach(self.currentViewData.categories, id: \.self){cat in
                                Text(cat.displayName).help(cat.displayName)
                                    .frame(width: 1170.0 * Double(cat.endIndx - cat.beginIndx) / Double(self.currentViewData.frames.count), height: 20)
                                    .background(Rectangle().fill(Color.gray))
                                    .foregroundColor(.black)
                                    .contextMenu {
                                        if self.currentViewData.categories.count > 1 {
                                            Button("Remove this section") {
                                                removeSection(cat)
                                            }
                                            Button("Keep this section only"){
                                                keepSection(cat)
                                            }
                                        }
                                    }
                                
                            }
                        }.padding(.horizontal)
                    }
                }
            }
            HStack(spacing: 5) {
                TextField("add a note", text: $editableNoteText, axis: .vertical)
                    .id("notetextfield")
                    .foregroundColor(.secondary)
                    .font(.system(.body))
                    .onSubmit(submitNote)
                    .focused($focusedField, equals: .noteField)
                    .frame(width: 1170)
                    .onAppear {
                        focusedField = Field.noteField
                    }
            }.padding(.horizontal)
            if !self.availableContextLevelActions.isEmpty {
                HStack(spacing: 5) {
                    if self.availableContextLevelActions.contains(.last_60s) {
                        Button("Last 60s", action: {setContextLevel(.last_60s)})
                            .disabled(self.currentContextLevel == .last_60s)
                            .buttonStyle(ContextActionButtonStyle(isSelected: self.currentContextLevel == .last_60s))
                        Divider()
                    }
                    if self.availableContextLevelActions.contains(.last_15s){
                        Button("Last 15s", action: {setContextLevel(.last_15s)})
                            .disabled(self.currentContextLevel == .last_15s)
                            .buttonStyle(ContextActionButtonStyle(isSelected: self.currentContextLevel == .last_15s))
                        Divider()
                    }
                    if self.availableContextLevelActions.contains(.last_screenshot){
                        Button("Last Screenshot", action: {setContextLevel(.last_screenshot)})
                            .disabled(self.currentContextLevel == .last_screenshot)
                            .buttonStyle(ContextActionButtonStyle(isSelected: self.currentContextLevel == .last_screenshot))
                        Divider()
                    }
                    if self.availableContextLevelActions.contains(.specific_frames){
                        TextField("search frames", text: $frameSearchString)
                            .onChange(of: frameSearchString, perform: {_ in
                                runFrameSearchQuery()
                            }).onSubmit(addFrameSearchResults)
                            .focused($focusedField, equals: .frameSearch)
                        Divider()
                    }
                    if self.currentContextLevel == .specific_frames {
                        // search specific actions
                        if self.addedFrameSearchStrings.count == 0 {
                            Button("Cancel", action: {
                                setContextLevel(.last_15s)
                                focusedField = .noteField
                            }).buttonStyle(ContextActionButtonStyle(isSelected: false))
                        }
                        Button("Add this search", action: {addFrameSearchResults()})
                            .buttonStyle(ContextActionButtonStyle(isSelected: false))
                        ForEach(self.addedFrameSearchStrings, id: \.self){ addedSearchTerm in
                            Text(addedSearchTerm)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 5)
                                .background(.gray)
                                .foregroundColor(.black)
                        }
                    }
                    
                    if self.screenRecorder.suggestionState == .not_asked {
                        Button("Remember", action: submitNote).frame(width: 1170 * 0.10)
                            .disabled(editableNoteText.count == 0 && self.currentViewData.frames.count == 0)
                            .buttonStyle(ContextActionButtonStyle(isSelected: false))
                    }
                    if self.currentContextLevel == .last_screenshot {
                        Button {
                            if self.screenRecorder.isErrorMessageFixerInitialized() {
                                self.runFixit()
                            } else {
                                self.presentApiKeySheet = true
                            }
                        } label: {
                            if self.screenRecorder.suggestionState == .done {
                                Text("Showing Fixit Suggestion Below")
                            } else if self.screenRecorder.suggestionState == .loading {
                                Text("Loading ...")
                            } else if self.screenRecorder.suggestionState == .not_asked {
                                Label("Fixit!", systemImage: "wand.and.stars")
                            }
                        }.buttonStyle(ContextActionButtonStyle(isSelected:  self.screenRecorder.suggestionState == .not_asked))
                        .sheet(isPresented: self.$presentApiKeySheet) {
                            self.screenRecorder.initializeErrorMessageFixer()
                            if self.screenRecorder.isErrorMessageFixerInitialized() {
                                self.runFixit()
                            }
                        } content: {
                            SettingsView(isPresented: self.$presentApiKeySheet, message: "Fixit needs an API Key from OpenAI. Please enter yours below.")
                        }

                    }
                }.padding(.horizontal).onChange(of: focusedField, perform: {[focusedField] val in
                    if focusedField != nil && val == .frameSearch {
                        setContextLevel(.specific_frames)
                    }
                })
            }
            if self.screenRecorder.suggestionState == .done {
                if let lastScreenshotFrame = self.currentViewData.frames.last {
                    if let fixits = lastScreenshotFrame.fixits?.allObjects as? Array<Fixit> {
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
            } else if self.screenRecorder.suggestionState == .loading {
                VStack(alignment: .leading){
                    Text(LocalizedStringKey("Loading..."))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .frame(width: 1170, height: 200, alignment: .leading)
                        .background(Rectangle().fill(Color.gray))
                }.padding()
            }
        }
        .padding(.vertical, 20)
        .onChange(of: self.screenRecorder.allFrameProcessingDone, perform: {_ in
            self.setFramesForContexts()
            self.setViewData()
        })
        .onChange(of: self.screenRecorder.lastFrameProcessingDone, perform: {_ in
            self.setFramesForContexts()
            self.setViewData()
        })
        .onAppear(perform: {
            self.setFramesForContexts()
            self.setViewData()
            setTimer()
        }).onReceive(self.refreshCategoriesTimer, perform: {_ in
            self.setViewData()
        })
        .textSelection(.enabled)
    }
}
