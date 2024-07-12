import XCTest
import JSONEquality
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
    
    func testChoiceTags() throws {
        let story = loadSampleStory()
        story.moveToKnitStitch("Choice")
        story.continueStory()
        print(story.options)
        XCTAssertGreaterThanOrEqual(story.options.count, 2)
        XCTAssertTrue(story.options[0].tags.keys.contains("option1Tag"))
        XCTAssertEqual(story.options[0].tags["option1Tag"], "option1TagValue")
        XCTAssertTrue(story.options[1].tags.keys.contains("option2Tag"))
        XCTAssertEqual(story.options[1].tags["option2Tag"], "option2Tag")
    }

    func testChoiceOnlySharedAndContentTag() throws {
        let story = loadSampleStory()
        story.moveToKnitStitch("Choice")
        story.continueStory()
        print(story.options)
        XCTAssertGreaterThanOrEqual(story.options.count, 3)
        XCTAssertEqual(story.options[2].tags.count, 2)
        XCTAssertTrue(story.options[2].tags.keys.contains("choice_tag"))
        XCTAssertEqual(story.options[2].tags["choice_tag"], "choice_tag")
        XCTAssertTrue(story.options[2].tags.keys.contains("shared_tag"))
        XCTAssertEqual(story.options[2].tags["shared_tag"], "shared_tag")
        story.chooseChoiceIndex(story.options[2].index)
        print(story.currentTags)
        XCTAssertEqual(story.currentTags.count, 2)
        XCTAssertTrue(story.currentTags.keys.contains("content_tag"))
        XCTAssertEqual(story.currentTags["content_tag"], "content_tag")
        XCTAssertTrue(story.currentTags.keys.contains("shared_tag"))
        XCTAssertEqual(story.currentTags["shared_tag"], "shared_tag")
    }
    

    
    // MARK: Variable tests
    func testGetVariable() throws {
        let story = loadSampleStory()
        story.continueStory()
        let jsValue = story.getVariable("stringVar")
        print(jsValue)
        let value = try story.getVariable("stringVar").string
        XCTAssertEqual(value, "Initial")
    }
    
    func testSetStringVariable() throws {
        let story = loadSampleStory()
        let oldValue = try story.getVariable("stringVar").string
        XCTAssertEqual(oldValue, "Initial")
        story.continueStory()
        story.setVariable("stringVar", to: "Value Set")
        let newValue = try story.getVariable("stringVar").string
        XCTAssertEqual(newValue, "Value Set")
    }
    
    func testSetIntVariable() throws {
        let story = loadSampleStory()
        let oldValue = try story.getVariable("intVar").int32
        XCTAssertEqual(oldValue, 0)
        story.continueStory()
        story.setVariable("intVar", to: 1)
        let newValue = try story.getVariable("intVar").int32
        XCTAssertEqual(newValue, 1)
    }
    
    func testSetDoubleVariable() throws {
        let story = loadSampleStory()
        let oldValue = try story.getVariable("doubleVar").double
        XCTAssertEqual(oldValue, 0.1)
        story.continueStory()
        story.setVariable("doubleVar", to: 1.1)
        let newValue = try story.getVariable("doubleVar").double
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
    
    func testObservedVariableChange() throws {
        let story = loadSampleStory()
        story.registerObservedVariable("observedVariable")
        XCTAssertTrue(story.oberservedVariables.keys.contains("observedVariable"))
        XCTAssertEqual(try story.oberservedVariables["observedVariable"]?.int32 ?? -1, 0)
        
        story.moveToKnitStitch("ObservedVariables")
        story.continueStory()
        XCTAssertEqual(try story.oberservedVariables["observedVariable"]?.int32 ?? -1, 1)
    }
    
    // MARK: Load/save state
//    private let compareJSON =
//        """
//        {
//          "jsonState" : "{\\"callstackThreads\\":{\\"threads\\":[{\\"callstack\\":[{\\"exp\\":false,\\"type\\":0,\\"temp\\":{}}],\\"threadIndex\\":0}],\\"threadCounter\\":0},\\"variablesState\\":{\\"stringVar\\":\\"^Initial\\",\\"intVar\\":2,\\"doubleVar\\":0.1,\\"observedVariable\\":0},\\"evalStack\\":[],\\"outputStream\\":[\\"^Initial\\",\\"\\\\n\\"],\\"currentChoices\\":[],\\"visitCounts\\":{\\"\\":1},\\"turnIndices\\":{},\\"turnIdx\\":-1,\\"storySeed\\":42,\\"previousRandom\\":0,\\"inkSaveVersion\\":8,\\"inkFormatVersion\\":19}",
//          "currentTags" : {
//
//          }
//        }
//        """

//    func compareJSON(_ json1: String, _ json2: String) -> Bool {
//        guard json1.count == json2.count else {
//            return false
//        }
//        
//        // perform a simple checksum to check for equality
//        var json1Counts = [Character: Int]()
//        for character in json1 {
//            json1Counts[character] = json1Counts[character, default: 0] + 1
//        }
//        
//        var json2Counts = [Character: Int]()
//        for character in json2 {
//            json2Counts[character] = json2Counts[character, default: 0] + 1
//        }
//        
//        return json1Counts == json2Counts
//    }
    
    func testSave() throws {
        let story = loadSampleStory()
        story.continueStory()
        story.setVariable("intVar", to: 2)
        let saveJSON = story.stateToJSON()
        let expectedJSON = loadCompareJSON()
        print(saveJSON, "\n\n", expectedJSON)
        XCTAssertTrue(try JSONEquality.JSONEquals(saveJSON, expectedJSON))
    }
    
    func testLoad() throws {
        let story = loadSampleStory()
        XCTAssertEqual(try story.getVariable("intVar").string, "0")
        
        let compareJSON = loadCompareJSON()
        story.loadState(compareJSON)
        story.continueStory()
        print(story.currentText)
        let intVarJS = story.getVariable("intVar")
        let intVar = try intVarJS.string
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
}
