//
//  Note.swift
//  encee
//
//  Created by Bharath Bhat on 2/9/23.
//

import Foundation
import CoreData

extension Note {
    
    static func createOrGet(_ context: NSManagedObjectContext) -> Note {
        let request = NSFetchRequest<Note>(entityName: "Note")
        let results = (try? context.fetch(request)) ?? []
        if let note = results.first {
            return note
        } else {
            let note = Note(context: context)
            note.createdAt = Date()
            note.updatedAt = Date()
            try? context.save()
            return note
        }
    }
    
    func getExistingEditableSnippet() -> Snippet? {
        guard let context = managedObjectContext else { return nil }
        let request = NSFetchRequest<Snippet>(entityName: "Snippet")
        request.predicate = NSPredicate(format: "editable = true and parentNote = %@", self)
        let results = (try? context.fetch(request)) ?? []
        guard let editableSnippet = results.first else { return nil }
        return editableSnippet
    }
    
    func appendSnippet() -> Snippet? {
        guard let context = managedObjectContext else {return nil}
        let snippet = Snippet(context: context)
        snippet.editable  = true
        snippet.createdAt = Date()
        snippet.parentNote = self
        snippet.text = ""
        
        snippet.snippetContext = SnippetContext(context: context)
        return snippet
    }
    
    var snippets: Array<Snippet> {
        get { snippets_!.array as! Array<Snippet> }
        set { snippets_ = NSOrderedSet(array: newValue) }
    }
    
    var snippetsCount: Int  {
        snippets.count
    }
 
}

