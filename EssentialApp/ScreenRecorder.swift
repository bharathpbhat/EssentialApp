//
//  ScreenRecorder.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 3/30/23.
//

import Foundation
import ScreenCaptureKit
import Combine
import OSLog
import SwiftUI
import AVKit

struct RunningAppTransition  {
    let runningApp: NSRunningApplication
    var timestamp: Date
}

struct RunningAppWindowTransition {
    let runningAppWindows: [SCWindow]
    var timestamp: Date // last time this was updated
}

enum SuggestionLoaderState {
    case not_asked, loading, done
}

struct FixitInputData {
    let frames: Array<ScreenshotFrame>
    let frameSearchStrings: Array<String>
    let contextLevel: ContextLevel
}

//  @MainActor
class ScreenRecorder: ObservableObject {
    
    // Last frame processing for fixit
    @Published var lastFrameProcessingDone: Bool = true
    @Published var allFrameProcessingDone: Bool = true
    
    // Fixit suggestion state
    @Published var suggestionState: SuggestionLoaderState = .not_asked
    
    // For pause recording
    @Published var isPausedByUser: Bool = false
    
    // For onboarding
    @Published var hasProcessedFrames: Bool = false
    
    // global note
    @Published var currentNote: Note
    
    @Published var usingSelf: Bool = true
    
    private var usingSelfStartTime: Date? = nil
    
    private var frameRate: Int = Constants.frameRate
    private var minFrameRate:Double = Constants.minFrameRate
    
    private var skippedFramesCount:Int = 0
    
    private var token: AnyCancellable? = nil
    private var timerCancellables: Array<Cancellable> = []
    
    private let managedObjectContext: NSManagedObjectContext
    private let postProcessor: PostProcessor
    private var errorMessageFixer: ErrorMessageFixer? = nil
   
    private let textRecognizer:TextRecognizer
    
    private var runningAppTransitions: Array<RunningAppTransition> = []
    private var runningAppWindowTransitions: Array<RunningAppWindowTransition> = []
    private var fixitInputData: FixitInputData? = nil
    
    init(context: NSManagedObjectContext){
        self.managedObjectContext = context
        self.postProcessor =  PostProcessor()
        self.currentNote = Note.createOrGet(self.managedObjectContext)
        self.textRecognizer = TextRecognizer()
        
        let defaults = UserDefaults.standard
        let onboardingComplete = defaults.bool(forKey: Constants.onboardingCompleteKey)
        
        self.initializeErrorMessageFixer()

        token = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).sink(receiveValue: { [weak self] note in
            guard let self = self else { return }
            guard !self.isPausedByUser else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else  { return }
           
            if app.bundleIdentifier == Bundle.main.bundleIdentifier {
                self.usingSelf = true
                self.usingSelfStartTime = Date()
                Task {
                    if self.isRunning {
                        await self.stop()
                        DispatchQueue.global(qos: .userInitiated).async {
                            Task {
                                let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                                LastFrameProcessor.run(context: backgroundContext, windowTransitions: self.runningAppWindowTransitions)
                                
                                DispatchQueue.main.async {
                                    self.lastFrameProcessingDone = true
                                }
                                await self.postProcessor.run(
                                    context: backgroundContext, windowTransitions: self.runningAppWindowTransitions, forceRun: true,
                                    processUptil: self.usingSelfStartTime)
                                DispatchQueue.main.async {
                                    self.allFrameProcessingDone = true
                                }
                            }
                        }
                        DispatchQueue.main.async {
                            self.suggestionState = .not_asked
                        }
                    }
                }
            } else {
                self.usingSelfStartTime = nil
                self.usingSelf = false
                self.lastFrameProcessingDone = false
                self.allFrameProcessingDone = false
                
                if let fixitInputData = self.fixitInputData {
                    saveSnippet(editableNoteText: "", frameIDs: fixitInputData.frames.map { $0.uuid! }, contextLevel: fixitInputData.contextLevel, frameSearchStrings: fixitInputData.frameSearchStrings, wasFixitRequested: true)
                }
                
                self.fixitInputData = nil
                
                Task {
                    await self.start()
                }
                
            }
                                        
            if let lastAppTransition = self.runningAppTransitions.last {
                if  lastAppTransition.runningApp.bundleIdentifier == app.bundleIdentifier {
                    _ = self.runningAppTransitions.popLast()
                }
            }
            self.runningAppTransitions.append(RunningAppTransition(runningApp: app, timestamp: Date()))
            
            self.setRunningAppWindowTransitions()
 
        })
        
        timerCancellables.append(Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink() {_ in
                DispatchQueue.global(qos: .utility).async {
                    Task {
                        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                        await self.postProcessor.run(context: backgroundContext, windowTransitions: self.runningAppWindowTransitions, forceRun: false, processUptil: self.usingSelfStartTime)
                    }
                }
        })
        
        // Clean up frames older than 5 min
        timerCancellables.append(Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink() {[weak self] _ in
                if let self = self {
                    if !self.usingSelf {
                        self.cleanupOlderFramesAndAssociatedData(cutoffTimeInterval: Constants.lookbackWindow)
                    }
                }
            })
                        
        // Adaptive frame rate
        timerCancellables.append(Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink() {[weak self] _ in
                if let self = self {
                    if !self.usingSelf {
                        self.setAdaptiveFrameRate()
                    }
                }
            })
        
        // Run once at init
        Task {
            // TODO: Replace with proper handling of unsaved frames
            self.cleanupUnCompactedFramesOnInit()
            self.cleanupOlderFramesAndAssociatedData(cutoffTimeInterval: Constants.lookbackWindow)
            self.checkIfProcessedFramesExist()
            if onboardingComplete {
                await self.refreshAvailableContent()
            }
        }
    }
    
    func initializeErrorMessageFixer() {
        let defaults = UserDefaults.standard
        let fixitApiKey = defaults.string(forKey: Constants.openAIApiKey)
        if fixitApiKey != nil {
            self.errorMessageFixer = ErrorMessageFixer()
        }
    }
    
    func isErrorMessageFixerInitialized() -> Bool {
        return self.errorMessageFixer != nil
    }
    
    func getErrorMessageFix(inputData: FixitInputData) {
        if let frame = inputData.frames.first, let errorMessageFixer = self.errorMessageFixer {
            self.suggestionState = .loading
            self.fixitInputData = inputData
            Task {
                await errorMessageFixer.getErrorMessageFix(frame: frame, context: self.managedObjectContext)
                DispatchQueue.main.async {
                    self.suggestionState = .done
                }
            }
        }
    }
    
    func setAdaptiveFrameRate() {
        let req = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        req.predicate = NSPredicate(format: "parentSnippetContext == nil && isCompacted = %@", NSNumber(value: false))
        let frames = (try? self.managedObjectContext.fetch(req)) ?? []
        var newFrameRate = self.frameRate
        var newMinFrameRate = self.minFrameRate
        if frames.count > 30 {
            newFrameRate = max(1, self.frameRate / 2)
            newMinFrameRate = max(0.15, self.minFrameRate / 2)
        } else {
            newFrameRate = min(Constants.frameRate, self.frameRate * 2)
            newMinFrameRate = min(Constants.minFrameRate, self.minFrameRate * 2)
        }
        if self.frameRate !=  newFrameRate {
            self.frameRate = newFrameRate
            updateEngine()
        }
        if self.minFrameRate != newMinFrameRate {
            self.minFrameRate = newMinFrameRate
        }
    }
    
    func cleanupUnusedFramesOnSave(frameIDs: Array<UUID>) {
        // Clean up other frames
        let cleanupRequest = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        cleanupRequest.predicate = NSPredicate(format: "parentSnippetContext == nil and not (uuid in %@)", frameIDs)
        let cleanupFrames = (try? self.managedObjectContext.fetch(cleanupRequest)) ?? []
        for frame in cleanupFrames {
            self.managedObjectContext.delete(frame)
        }
    }
    
    func cleanupUnCompactedFramesOnInit() {
        let cleanupRequest = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        cleanupRequest.predicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@", NSNumber(value: false))
        let cleanupFrames = (try? self.managedObjectContext.fetch(cleanupRequest)) ?? []
        for frame in cleanupFrames {
            self.managedObjectContext.delete(frame)
        }
    }
    
    func checkIfProcessedFramesExist() {
        let request = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        request.predicate = NSPredicate(format: "parentSnippetContext == nil and isCompacted = %@", NSNumber(value: true))
        let frames = (try? self.managedObjectContext.fetch(request)) ?? []
        if !frames.isEmpty {
            DispatchQueue.main.async {
                self.hasProcessedFrames = true
            }
        }
    }
    
    func cleanupOlderFramesAndAssociatedData(cutoffTimeInterval: TimeInterval) {
        let cutoffTime = Date().addingTimeInterval(-cutoffTimeInterval)
        let cleanupRequest = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        cleanupRequest.predicate = NSPredicate(format: "parentSnippetContext == nil and createdAt < %@", cutoffTime as NSDate)
        let cleanupFrames = (try? self.managedObjectContext.fetch(cleanupRequest)) ?? []
        for frame in cleanupFrames {
            self.managedObjectContext.delete(frame)
        }
        
        do {
            try self.managedObjectContext.save()
        } catch {
            print("Clean up of older frames failed with \(error)")
        }
        
        self.runningAppTransitions = self.runningAppTransitions.filter { $0.timestamp >= cutoffTime }
        self.runningAppWindowTransitions = self.runningAppWindowTransitions.filter { $0.timestamp >= cutoffTime }
    }
    
    func saveSnippet(editableNoteText: String, frameIDs: Array<UUID>, contextLevel: ContextLevel, frameSearchStrings: Array<String> = [], wasFixitRequested:Bool = false) {
        guard let snippet = currentNote.appendSnippet() else { return }
        guard let snippetContext = snippet.snippetContext else { return }
        snippet.text = editableNoteText
        snippet.editable = false
        
        snippetContext.contextLevel = contextLevel.rawValue
        snippetContext.wasFixitRequested = wasFixitRequested
        for frameSearchString in frameSearchStrings {
            let frameSearchStringObj = FrameSearchString(context: self.managedObjectContext)
            frameSearchStringObj.query = frameSearchString
            frameSearchStringObj.parentSnippetContext = snippetContext
        }
        
        let request = NSFetchRequest<ScreenshotFrame>(entityName: "ScreenshotFrame")
        request.predicate = NSPredicate(format: "parentSnippetContext == nil and uuid in %@", frameIDs)
        let frames = (try? self.managedObjectContext.fetch(request)) ?? []
        for frame in frames {
            frame.parentSnippetContext = snippetContext
        }
        
        cleanupUnusedFramesOnSave(frameIDs: frameIDs)
        
        do {
            try self.managedObjectContext.save()
        } catch  {
            print("snippet save failed \(error)")
            return
        }
        
        self.runningAppTransitions = []
        self.runningAppWindowTransitions = []
        
        snippet.runAccurateOcr()
    }
    
    private func getDirtyRectsFractionOfDisplay(_ frame: CapturedFrame) -> Double? {
        guard let display = selectedDisplay else { return nil }
        return frame.dirtyRectsTotalArea / Double(display.width * display.height * scaleFactor * scaleFactor)
    }
    
    func shouldIncludeFrame(_ frame: CapturedFrame) -> Bool {
        guard let dirtyRectsFractionOfDisplay = getDirtyRectsFractionOfDisplay(frame) else {
            return true
        }
        
        if dirtyRectsFractionOfDisplay < Constants.dirtyRectsFractionThreshold {
            self.skippedFramesCount += 1
            if Double(self.skippedFramesCount) >= Double(self.frameRate) / self.minFrameRate {
                self.skippedFramesCount = 0
                return true
            }
            else {
                return false
            }
        }
        return true
    }
    
    func processFrame(_ frame: CapturedFrame){
        DispatchQueue.main.async {
            self.hasProcessedFrames = true
        }
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                var shouldRefreshAvailableContent: Bool = false
                await backgroundContext.perform {
                    let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer!)
                    
                    let context = CIContext(options: nil)
                    
                    let pngImageData = context.pngRepresentation(of: ciImage, format: CIFormat.RGBA16, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                    let screenshotFrame = ScreenshotFrame(context: backgroundContext)
                    screenshotFrame.uuid = UUID()
                    screenshotFrame.createdAt = Date()
                    screenshotFrame.image = pngImageData
                    screenshotFrame.displayTime = Int64(frame.displayTime)
                    screenshotFrame.isCompacted = false
                    screenshotFrame.areOcrBoxesCompacted = false
                    screenshotFrame.dirtyRectsFractionOfDisplay = self.getDirtyRectsFractionOfDisplay(frame) ?? -1.0
                    screenshotFrame.height = frame.size.height
                    screenshotFrame.width = frame.size.width
                                
                    do {
                        try backgroundContext.save()
                    } catch {
                        print ("screenshot frame save failed: \(error)")
                    }

                    shouldRefreshAvailableContent = screenshotFrame.dirtyRectsFractionOfDisplay >= 0.5
                }
                if shouldRefreshAvailableContent {
                    await self.refreshAvailableContent()
                }
            }
        }
    }
    
    /// The supported capture types.
    enum CaptureType {
        case display
    }
    
    private let logger = Logger()
    
    var isRunning = false
    
    // MARK: - Video Properties
    var captureType: CaptureType = .display {
        didSet { updateEngine() }
    }
    
    @Published var selectedDisplay: SCDisplay? {
        didSet { updateEngine() }
    }
    
    var selectedWindow: SCWindow? {
        didSet { updateEngine() }
    }
    
    var contentSize = CGSize(width: 1, height: 1)
    private var scaleFactor: Int { Int(NSScreen.main?.backingScaleFactor ?? 2) }
    
    private var availableApps = [SCRunningApplication]()
    private(set) var availableDisplays = [SCDisplay]()
    private(set) var availableWindows = [SCWindow]()
    
    // The object that manages the SCStream.
    private let captureEngine = CaptureEngine()
    
    var doWeHavePermissions = true
    
    func setPermissionsBit(_ doWeHavePermissions: Bool) {
        self.doWeHavePermissions = doWeHavePermissions
    }
    
    var canRecord: Bool {
        get async {
            do {
                // If the app doesn't have Screen Recording permission, this call generates an exception.
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                return false
            }
        }
    }
    
    /// Starts capturing screen content.
    func start() async {
        // Exit if not set up.
        guard doWeHavePermissions else { return }
        
        // This can happen when apple's SCStreamConfiguration API hangs
        guard selectedDisplay != nil else { return }
        
        // Exit early if already running.
        guard !isRunning else { return }
        
        guard !isPausedByUser else { return }
        
        do {
            let config = streamConfiguration
            let filter = contentFilter
            // Update the running state.
            isRunning = true
            // Start the stream and await new video frames.
            for try await frame in captureEngine.startCapture(configuration: config, filter: filter) {
                if shouldIncludeFrame(frame) {
                    processFrame(frame)
                    if contentSize != frame.size {
                        // Update the content size if it changed.
                        contentSize = frame.size
                    }
                }
            }
        } catch {
            logger.error("\(error.localizedDescription)")
            // Unable to start the stream. Set the running state to false.
            isRunning = false
        }
    }
    
    /// Stops capturing screen content.
    func stop() async {
        guard isRunning else { return }
        await captureEngine.stopCapture()
        isRunning = false
    }
    
    /// - Tag: UpdateCaptureConfig
    private func updateEngine() {
        guard doWeHavePermissions else { return }
        guard selectedDisplay != nil else { return }
        guard isRunning else { return }
        Task {
            await captureEngine.update(configuration: streamConfiguration, filter: contentFilter)
        }
    }
    
    /// - Tag: UpdateFilter
    private var contentFilter: SCContentFilter {
        let filter: SCContentFilter
        switch captureType {
        case .display:
            guard let display = selectedDisplay else { fatalError("No display selected.") }
            var excludedApps = [SCRunningApplication]()
            excludedApps = availableApps.filter { app in
                Bundle.main.bundleIdentifier == app.bundleIdentifier || app.bundleIdentifier == "com.apple.dock" || app.applicationName == ""
            }
            // Create a content filter with excluded apps.
            filter = SCContentFilter(display: display,
                                     excludingApplications: excludedApps,
                                     exceptingWindows: [])
        }
        return filter
    }
    
    private var streamConfiguration: SCStreamConfiguration {
        
        let streamConfig = SCStreamConfiguration()
        
        // Configure the display content width and height.
        if captureType == .display, let display = selectedDisplay {
            streamConfig.width = display.width * scaleFactor
            streamConfig.height = display.height * scaleFactor
        }
        
        // Set the capture interval at 6 fps.
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(self.frameRate))
        
        // Increase the depth of the frame queue to ensure high fps at the expense of increasing
        // the memory footprint of WindowServer.
        streamConfig.queueDepth = 5
        
        return streamConfig
    }
    
    private func setRunningAppWindowTransitions() -> Void {
        guard let lastRunningAppTransition = self.runningAppTransitions.last else { return }
        
        let runningAppWindows = availableWindows.filter { $0.owningApplication?.bundleIdentifier == lastRunningAppTransition.runningApp.bundleIdentifier &&  ($0.title?.count ?? 0) >  0 }
        
        if runningAppWindows.count == 0 { return }
        
        if let lastTransition = self.runningAppWindowTransitions.last {
            if Set<String?>(lastTransition.runningAppWindows.map({ $0.title })) == Set<String?>(runningAppWindows.map({ $0.title })){
                _ = self.runningAppWindowTransitions.popLast()
            }
        }
            
        self.runningAppWindowTransitions.append(RunningAppWindowTransition(runningAppWindows: runningAppWindows, timestamp: Date()))
    }
    
    /// - Tag: GetAvailableContent
    private func refreshAvailableContent() async {
        do {
            // Retrieve the available screen content to capture.
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                        onScreenWindowsOnly: true)
            availableDisplays = availableContent.displays
            
            let windows = filterWindows(availableContent.windows)
            if windows != availableWindows {
                availableWindows = windows
            }
            availableApps = availableContent.applications
            
            if selectedDisplay == nil {
                DispatchQueue.main.async {
                    self.selectedDisplay = self.availableDisplays.first
                }
            }
            if selectedWindow == nil {
                selectedWindow = availableWindows.first
            }
            
            setRunningAppWindowTransitions()
        } catch {
            logger.error("Failed to get the shareable content: \(error.localizedDescription)")
        }
    }
    
    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows
        // Sort the windows by app name.
            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
        // Remove windows that don't have an associated .app bundle.
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
        // Remove this app's window from the list.
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
}

extension SCWindow {
    var displayName: String {
        switch (owningApplication, title) {
        case (.some(let application), .some(let title)):
            return "\(application.applicationName): \(title)"
        case (.none, .some(let title)):
            return title
        case (.some(let application), .none):
            return "\(application.applicationName): \(windowID)"
        default:
            return ""
        }
    }
}

extension SCDisplay {
    var displayName: String {
        "Display: \(width) x \(height)"
    }
}
