//
//  PostProcessor.swift
//  EssentialApp
//
//  Created by Bharath Bhat on 3/10/23.
//

import Foundation
import CoreData


class PostProcessor {
    
    private let compactor:Compactor
    private let appTransitionsLinker: AppTransitionsLinker
    
    private var numRunningInstances:Int = 0
    
    init(){
        self.compactor = Compactor()
        self.appTransitionsLinker = AppTransitionsLinker()
    }
    
    func run(context: NSManagedObjectContext, windowTransitions: Array<RunningAppWindowTransition>,
             forceRun:Bool=false, processUptil: Date?=nil) async {
        if self.numRunningInstances > 0 {
            if !forceRun { return }
        }
        numRunningInstances += 1
        await self.compactor.run(context: context, processUptil: processUptil)
        await self.appTransitionsLinker.run(context: context, windowTransitions: windowTransitions, processUptil: processUptil)
        numRunningInstances -= 1
    }
}
