//
//  ContentView.swift
//  encee
//
//  Created by Bharath Bhat on 2/2/23.
//

import SwiftUI
import CoreData

class SnippetData: ObservableObject, Hashable, Equatable {
    @Published var snippet: Snippet
    @Published var relevantOcrBoxes: Array<Array<RecognizedText>>
    
    init(snippet: Snippet, relevantOcrBoxes: Array<Array<RecognizedText>>){
        self.snippet = snippet
        self.relevantOcrBoxes = relevantOcrBoxes
    }
    
    static func ==(lhs: SnippetData, rhs: SnippetData) -> Bool {
        return lhs.snippet.objectID == rhs.snippet.objectID
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(snippet.objectID)
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @ObservedObject var screenRecorder: ScreenRecorder
    @FetchRequest var snippets: FetchedResults<Snippet>
    @State var noteSearchString: String = ""
    @State var searchResults: Array<Snippet> = []
    @State var ocrBoxesForSearchResults: Array<Array<Array<RecognizedText>>> = []
    
    @State var presentOnboardingSheet: Bool = false;
    @State var presentSettingsSheet: Bool = false;
    
    init(_ screenRecorder: ScreenRecorder){
        self.screenRecorder = screenRecorder
        let predicate = NSPredicate(format: "parentNote = %@", screenRecorder.currentNote)
        self._snippets = FetchRequest(entity: Snippet.entity(), sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)], predicate: predicate)
    }
    
    func checkOnboardingStatus(){
        let defaults = UserDefaults.standard
        let onboardingComplete: Bool = defaults.bool(forKey: Constants.onboardingCompleteKey)
        
        if onboardingComplete {
            Task {
                if await screenRecorder.canRecord {
                    screenRecorder.setPermissionsBit(true)
                } else {
                    screenRecorder.setPermissionsBit(false)
                }
            }
        } else {
            self.presentOnboardingSheet = true
        }
    }
   
    func runSearchOnSnippets() {
        let request = NSFetchRequest<Snippet>(entityName: "Snippet")
        request.predicate = NSPredicate(format: "parentNote = %@ and (text_ contains[c] %@ OR SUBQUERY(snippetContext.screenshotFrames_, $sf, $sf.fastTranscript contains[c] %@).@count > 0)", screenRecorder.currentNote, noteSearchString, noteSearchString)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        self.searchResults = (try? self.viewContext.fetch(request)) ?? []
        
        var relevantOcrBoxes: Array<Array<Array<RecognizedText>>> = []
        for snippet in self.searchResults {
            if let snippetContext = snippet.snippetContext {
                var snippetOcrBoxes: Array<Array<RecognizedText>> = []
                for frame in snippetContext.screenshotFrames {
                    let modelType = frame.accurateTranscriptHash == nil ? "fast" : "accurate"
                    let ocrReq = NSFetchRequest<RecognizedText>(entityName: "RecognizedText")
                    ocrReq.predicate = NSPredicate(format: "modelType == %@ and parentScreenshotFrame == %@ and text_ contains[c] %@", modelType, frame, noteSearchString)
                    snippetOcrBoxes.append((try? self.viewContext.fetch(ocrReq)) ?? [])
                }
                relevantOcrBoxes.append(snippetOcrBoxes)
            }
        }
        self.ocrBoxesForSearchResults = relevantOcrBoxes
    }
    
    var snippetsToShow: Array<SnippetData> {
        if noteSearchString.count > 0 {
            var ret:Array<SnippetData> = []
            for indx in 0..<self.searchResults.count {
                ret.append(SnippetData(snippet: self.searchResults[indx], relevantOcrBoxes: self.ocrBoxesForSearchResults[indx]))
            }
            return ret
        } else {
            return self.snippets.map { SnippetData(snippet: $0, relevantOcrBoxes: []) }
        }
    }
    
    var placeholderText: String? {
        if !self.snippetsToShow.isEmpty { return nil }
        
        if self.noteSearchString.count > 0 { return "No results for your search term." }
        
        if screenRecorder.hasProcessedFrames {
            return nil
        } else {
            if screenRecorder.selectedDisplay == nil {
                return """
                Loading...
                
                If you are stuck here for a while, please quit the app and launch again. It sometimes takes a while for the app to know that it has screen recording permissions. Sorry about that.
                """
            } else {
                return  """
                Set up is complete! Keep this app running, and go about your work. When you need to remember something on your screen, or fix an error message that you run into, \u{2318}-tab back to this app.
                
                Test it out by switching to a different window, and then coming back here.
                """
            }
        }
    }
    
    func showSettings(){
        self.presentSettingsSheet = true
    }
    
    var body: some View {
        HSplitView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        if let placeholderText = self.placeholderText {
                            VStack() {
                                Text(placeholderText)
                                    .padding(.horizontal)
                                    .padding(.vertical)
                                    .font(.title3)
                                    .lineSpacing(10)
                            }.frame(maxWidth: .infinity, minHeight: 900, maxHeight: .infinity, alignment: Alignment.bottomLeading)
                        } else {
                            ForEach(self.snippetsToShow, id: \.self){snippetData in
                                SnippetView(snippetData: snippetData)
                            }
                        }
                        if noteSearchString.count == 0 && screenRecorder.usingSelf {
                            EditableSnippetView(screenRecorder: screenRecorder).id("editable")
                        }
                    }.searchable(text: $noteSearchString, prompt: "Search all your notes")
                        .frame(minHeight: 900, maxHeight: .infinity, alignment: .bottomTrailing)
                }.toolbar {
                    ToolbarItem {
                        Button {
                            showSettings()
                        } label: {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                    }
                    ToolbarItem {
                        Button {
                            screenRecorder.isPausedByUser.toggle()
                        } label: {
                            if screenRecorder.isPausedByUser {
                                Label("Unpause Screen Capture", systemImage: "play.circle")
                            } else {
                                Label("Pause Screen Capture", systemImage: "pause.circle")
                            }
                        }
                        /*
                        Button(screenRecorder.isPausedByUser ? "Unpause Screen Capture" : "Pause Screen Capture") {
                            screenRecorder.isPausedByUser = !screenRecorder.isPausedByUser
                        }.buttonStyle(ContextActionButtonStyle(isSelected: false))
                         */
                    }
                }
                .onAppear {
                    proxy.scrollTo("editable", anchor: .bottom)
                }.onChange(of: self.snippets.count){_  in
                    proxy.scrollTo("editable", anchor: .bottom)
                }.onChange(of: self.screenRecorder.suggestionState){_ in
                    proxy.scrollTo("editable", anchor: .bottom)
                }.onChange(of: self.screenRecorder.lastFrameProcessingDone){_ in
                    proxy.scrollTo("editable", anchor: .bottom)
                }.onChange(of: self.screenRecorder.usingSelf){val in
                    if val {
                        proxy.scrollTo("editable", anchor: .bottom)
                    }
                }.onChange(of: noteSearchString, perform: {newval in
                    runSearchOnSnippets()
                    if newval.count == 0 {
                        proxy.scrollTo("editable", anchor: .bottom)
                    }
                })
            }
        }
        .sheet(isPresented: self.$presentOnboardingSheet) {
                                // print("Sheet dismissed")
        } content: {
            OnboardingView(isPresented: self.$presentOnboardingSheet, screenRecorder: self.screenRecorder)
        }
        .sheet(isPresented: self.$presentSettingsSheet) {
            self.screenRecorder.initializeErrorMessageFixer()
        } content: {
            SettingsView(isPresented: self.$presentSettingsSheet)
        }
        .onAppear (perform: {
            checkOnboardingStatus()
        })
        .onChange(of: self.presentOnboardingSheet, perform: {_ in
            checkOnboardingStatus()
        })
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
