//
//  CombineTests.swift
//  
//
//  Created by Maarten Engels on 16/02/2021.
//

import XCTest
import Combine
@testable import InkSwift

final class CombineTests: XCTestCase {
    
    /*
    @Published var globalTags: [String: String]
    @Published var currentErrors: [String]
    
    // these need to be persisted
    @Published var oberservedVariables: [String: JSValue]
 */
    
    var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        cancellables.removeAll()
    }
    
    // MARK: Tests
    func testCurrentTextChangedStory() throws {
        
        
        let story = loadSampleStory()
        story.moveToKnitStitch("Knot2")
        let oldText = story.currentText
        var newText = oldText
        story.$currentText.sink(receiveValue: { text in
            newText = text
        }).store(in: &cancellables)
        
        story.continueStory()
        
        XCTAssertNotEqual(oldText, newText)
    }
    
    func testCanContinueChangedStory() throws {
        let story = loadSampleStory()
        story.moveToKnitStitch("Knot2")
        let oldCanContinue = story.canContinue
        var newCanContinue = oldCanContinue
        story.$canContinue.sink(receiveValue: { canContinue in
            newCanContinue = canContinue
        }).store(in: &cancellables)
        
        story.continueStory()
        story.continueStory()
        
        XCTAssertNotEqual(oldCanContinue, newCanContinue)
    }
    
    func testOptionsChangedStory() throws {
        let story = loadSampleStory()
        let oldOptions = story.options
        var newOptions = oldOptions
        
        story.moveToKnitStitch("Choice")
        story.$options.sink(receiveValue: { o in
            newOptions = o
        }).store(in: &cancellables)
        
        story.continueStory()
        story.continueStory()
        
        print(oldOptions)
        print(newOptions)
        XCTAssertNotEqual(oldOptions.count, newOptions.count)
    }
    
    func testCurrentTagsChanges() throws {
        let story = loadSampleStory()
        let oldTags = story.currentTags
        var newTags = oldTags
        
        story.moveToKnitStitch("Tags", stitch: "EmptyTag")
        story.$currentTags.sink(receiveValue: { o in
            newTags = o
        }).store(in: &cancellables)
        
        story.continueStory()
        story.continueStory()
        
        print(oldTags)
        print(newTags)
        XCTAssertNotEqual(oldTags.count, newTags.count)
    }
    
    func testOberservedVariables() throws {
        let story = loadSampleStory()
        story.registerObservedVariable("observedVariable")
        let old_observedVariable = story.oberservedVariables["observedVariable"]?.toInt32() ?? -1
        var new_observedVariable = old_observedVariable
        
        story.moveToKnitStitch("ObservedVariables")
        story.$oberservedVariables.sink(receiveValue: { o in
            new_observedVariable = o["observedVariable"]?.toInt32() ?? -1
        }).store(in: &cancellables)
        
        story.continueStory()
        story.continueStory()
        
        print(old_observedVariable)
        print(new_observedVariable)
        XCTAssertNotEqual(old_observedVariable, new_observedVariable)
    }
    
    func testSetObservedVariableTriggersCombine() throws {
        let story = loadSampleStory()
        story.registerObservedVariable("observedVariable")
        let old_observedVariable = story.oberservedVariables["observedVariable"]?.toInt32() ?? -1
        
        var new_observedVariable = old_observedVariable
        story.$oberservedVariables.sink(receiveValue: { o in
            new_observedVariable = o["observedVariable"]?.toInt32() ?? -1
        }).store(in: &cancellables)
            
        story.setVariable("observedVariable", to: 1)
        

        XCTAssertNotEqual(old_observedVariable, new_observedVariable)
    }

    // MARK: Misc stuff
    private func loadSampleStory() -> InkStory {
        let story = InkStory()
        
        guard let url = Bundle.module.url(forResource: "test.ink", withExtension: "json") else {
            fatalError("Could not find ink story file.")
        }
        
        do {
            let storyJSON = try String(contentsOf: url)
            story.loadStory(json: storyJSON)
            story.continueStory()
            return story
        } catch {
            fatalError("Failed to load story: \(error)")
        }
    }
    
    static var allTests = [
        ("testCurrentTextChangedStory", testCurrentTextChangedStory),
        ("testCanContinueChangedStory", testCanContinueChangedStory),
        ("testOptionsChangedStory", testOptionsChangedStory),
        ("testCurrentTagsChanges", testCurrentTagsChanges),
        ("testOberservedVariables", testOberservedVariables),        
    ]
}
