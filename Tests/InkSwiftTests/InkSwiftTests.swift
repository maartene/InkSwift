import XCTest
@testable import InkSwift

final class InkSwiftTests: XCTestCase {
    
    // MARK: Setup tests
    func testCreateInkStory() throws {
        let story = InkStory()
        print(story)
    }
    
    func testLoadInkStory() throws {
        let story = loadSampleStory()
        print(story.currentText)
        XCTAssertEqual(story.currentText, "Line 1\n")
    }
    
    // MARK: Knot/stitch tests
    func testGoToKnot() throws {
        let story = loadSampleStory()
        story.moveToKnitStitch("Knot1")
        story.continueStory()
        print(story.currentText)
        XCTAssertEqual(story.currentText, "Move to knot1\n")
    }
    
    func testGoToKnotStitch() throws {
        let story = loadSampleStory()
        story.moveToKnitStitch("Knot2", stitch: "stitch1")
        story.continueStory()
        print(story.currentText)
        XCTAssertEqual(story.currentText, "You are now at stitch 1\n")
    }
    
    // MARK: Choice tests
    func testSeeChoices() throws {
        let story = loadSampleStory()
        story.moveToKnitStitch("Choice")
        story.continueStory()
        print(story.options)
        XCTAssertEqual(story.currentText, "Choice 1\n")
        XCTAssertGreaterThan(story.options.count, 0)
        XCTAssertFalse(story.canContinue)
    }
    
    func testChooseChoiseOption() throws {
        let story = loadSampleStory()
        story.moveToKnitStitch("Choice")
        
        story.continueStory()
        XCTAssertGreaterThan(story.options.count, 0)
        
        story.chooseChoiceIndex(1)
        story.continueStory()
        XCTAssertEqual(story.currentText, "You chose option 2\n")
    }
    
    // MARK: Tag tests
    func testTag() throws {
        let story = loadSampleStory()
        XCTAssertEqual(story.currentTags.count, 0)
        story.moveToKnitStitch("Tags", stitch: "EmptyTag")
        
        XCTAssertGreaterThan(story.currentTags.count, 0)
        XCTAssertTrue(story.currentTags.keys.contains("testTag"))
    }
    
    func testValueTag() throws {
        let story = loadSampleStory()
        XCTAssertEqual(story.currentTags.count, 0)
        story.moveToKnitStitch("Tags", stitch: "ValueTag")
        
        XCTAssertGreaterThan(story.currentTags.count, 0)
        XCTAssertTrue(story.currentTags.keys.contains("testTag2"))
        XCTAssertEqual(story.currentTags["testTag2"], "tag2Value")
    }
    
    func testRetainTag() throws {
        let story = loadSampleStory()
        XCTAssertTrue(story.retainTags.contains("IMAGE"))
        XCTAssertEqual(story.currentTags.count, 0)
        story.moveToKnitStitch("Tags", stitch: "RetainTag")
        XCTAssertGreaterThan(story.currentTags.count, 0)
        XCTAssertTrue(story.currentTags.keys.contains("IMAGE"))
        XCTAssertEqual(story.currentTags["IMAGE"], "retain.png")
        story.continueStory()
        XCTAssertTrue(story.currentTags.keys.contains("IMAGE"))
        XCTAssertEqual(story.currentTags["IMAGE"], "retain.png")
    }
    
    func testNonRetainTag() throws {
        let story = loadSampleStory()
        XCTAssertFalse(story.retainTags.contains("nonRetainTag"))
        XCTAssertEqual(story.currentTags.count, 0)

        story.moveToKnitStitch("Tags", stitch: "NonRetainTag")
        XCTAssertGreaterThan(story.currentTags.count, 0)
        XCTAssertTrue(story.currentTags.keys.contains("nonRetainTag"))
        XCTAssertEqual(story.currentTags["nonRetainTag"], "dontretain.wav")

        story.continueStory()
        XCTAssertFalse(story.currentTags.keys.contains("nonRetainTag"))
        XCTAssertEqual(story.currentTags.count, 0)
    }
    
    // MARK: Variable tests
    func testGetVariable() {
        let story = loadSampleStory()
        story.continueStory()
        let jsValue = story.getVariable("stringVar")
        print(jsValue)
        let value = story.getVariable("stringVar").toString()
        XCTAssertEqual(value, "Initial")
    }
    
    func testSetStringVariable() {
        let story = loadSampleStory()
        let oldValue = story.getVariable("stringVar").toString()
        XCTAssertEqual(oldValue, "Initial")
        story.continueStory()
        story.setVariable("stringVar", to: "Value Set")
        let newValue = story.getVariable("stringVar").toString()
        XCTAssertEqual(newValue, "Value Set")
    }
    
    func testSetIntVariable() {
        let story = loadSampleStory()
        let oldValue = story.getVariable("intVar").toInt32()
        XCTAssertEqual(oldValue, 0)
        story.continueStory()
        story.setVariable("intVar", to: 1)
        let newValue = story.getVariable("intVar").toInt32()
        XCTAssertEqual(newValue, 1)
    }
    
    func testSetDoubleVariable() {
        let story = loadSampleStory()
        let oldValue = story.getVariable("doubleVar").toDouble()
        XCTAssertEqual(oldValue, 0.1)
        story.continueStory()
        story.setVariable("doubleVar", to: 1.1)
        let newValue = story.getVariable("doubleVar").toDouble()
        XCTAssertEqual(newValue, 1.1)
    }
    
    
        
    // MARK: Observed variables
    func testRegisterObservedVariable() {
        let story = loadSampleStory()
        XCTAssertFalse(story.oberservedVariables.keys.contains("observedVariable"))
        
        story.registerObservedVariable("observedVariable")
        XCTAssertTrue(story.oberservedVariables.keys.contains("observedVariable"))
    }
    
    func testDeRegisterObservedVariable() {
        let story = loadSampleStory()
        story.registerObservedVariable("observedVariable")
        XCTAssertTrue(story.oberservedVariables.keys.contains("observedVariable"))
        
        story.deregisterObservedVariable("observedVariable")
        XCTAssertFalse(story.oberservedVariables.keys.contains("observedVariable"))
    }
    
    func testObservedVariableChange() {
        let story = loadSampleStory()
        story.registerObservedVariable("observedVariable")
        XCTAssertTrue(story.oberservedVariables.keys.contains("observedVariable"))
        XCTAssertEqual(story.oberservedVariables["observedVariable"]?.toInt32() ?? -1, 0)
        
        story.moveToKnitStitch("ObservedVariables")
        story.continueStory()
        XCTAssertEqual(story.oberservedVariables["observedVariable"]?.toInt32() ?? -1, 1)
    }
    
    // MARK: Load/save state
    private let compareJSON =
        """
        {
          "jsonState" : "{\\"callstackThreads\\":{\\"threads\\":[{\\"callstack\\":[{\\"exp\\":false,\\"type\\":0,\\"temp\\":{}}],\\"threadIndex\\":0}],\\"threadCounter\\":0},\\"variablesState\\":{\\"stringVar\\":\\"^Initial\\",\\"intVar\\":2,\\"doubleVar\\":0.1,\\"observedVariable\\":0},\\"evalStack\\":[],\\"outputStream\\":[\\"^Initial\\",\\"\\\\n\\"],\\"currentChoices\\":[],\\"visitCounts\\":{\\"\\":1},\\"turnIndices\\":{},\\"turnIdx\\":-1,\\"storySeed\\":42,\\"previousRandom\\":0,\\"inkSaveVersion\\":8,\\"inkFormatVersion\\":19}",
          "currentTags" : {

          }
        }
        """
    
    func testSave() {
        let story = loadSampleStory()
        story.continueStory()
        story.setVariable("intVar", to: 2)
        let saveJSON = story.stateToJSON()
        let compareJSON = loadCompareJSON()
        print(saveJSON)
        XCTAssertEqual(saveJSON + "\n", compareJSON)
    }
    
    func testLoad() {
        let story = loadSampleStory()
        let compareJSON = loadCompareJSON()
        story.loadState(compareJSON)
        story.continueStory()
        print(story.currentText)
        let intVarJS = story.getVariable("intVar")
        let intVar = intVarJS.toString()
        XCTAssertEqual(intVar, "2")
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

    private func loadCompareJSON() -> String {
        guard let url = Bundle.module.url(forResource: "compare", withExtension: "json") else {
            fatalError("Could not find compare JSON file.")
        }
        
        do {
            let compareJSON = try String(contentsOf: url)
            return compareJSON
        } catch {
            fatalError("Failed to load compare JSON: \(error)")
        }
    }
    
    static var allTests = [
        ("testCreateInkStory", testCreateInkStory),
        ("testLoadInkStory", testLoadInkStory),
        ("testGoToKnot", testGoToKnot),
        ("testGoToKnotStitch", testGoToKnotStitch),
        ("testSeeChoices", testSeeChoices),
        ("testChooseChoiseOption", testChooseChoiseOption),
        ("testTag", testTag),
        ("testValueTag", testValueTag),
        ("testRetainTag", testRetainTag),
        ("testNonRetainTag", testNonRetainTag),
        ("testSetStringVariable", testSetStringVariable),
        ("testSetIntVariable", testSetIntVariable),
        ("testSetDoubleVariable", testSetDoubleVariable),
        ("testGetVariable", testGetVariable),
        ("testRegisterObservedVariable", testRegisterObservedVariable),
        ("testDeRegisterObservedVariable", testDeRegisterObservedVariable),
        ("testObservedVariableChange", testObservedVariableChange),
        ("testSave", testSave),
        ("testLoad", testLoad),
    ]
}
