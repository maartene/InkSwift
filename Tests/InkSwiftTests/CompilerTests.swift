//
//  CompilerTests.swift
//  
//
//  Created by Maarten Engels on 17/05/2022.
//

import XCTest
@testable import InkSwift

final class CompilerTests: XCTestCase {
    
    let testInk =
    """
    Hello, World!
    -> END
    """
    
    func testCompileHelloWorld() {
        let inkStory = InkStory()
        inkStory.loadStory(ink: testInk)
        // If the story compiles correctly, the first line should now be available.
        XCTAssertEqual(inkStory.currentText.trimmingCharacters(in: .whitespacesAndNewlines), "Hello, World!")
    }
    
    /// I use TheIntercept as a test case, because it's a pretty complicated Ink story that highlights many of its features. If this one compiles, I am fairly certain other Ink stories also compile.
    func testCompileTheIntercept() throws {
        guard let url = Bundle.module.url(forResource: "TheIntercept", withExtension: "ink") else {
            XCTFail("Could not find ink story file.")
            return
        }
        
        let inkStory = InkStory()
        let storyInk = try String(contentsOf: url)
        inkStory.loadStory(ink: storyInk)
        // If the story compiles correctly, the first line should now be available.
        XCTAssertEqual(inkStory.currentText.trimmingCharacters(in: .whitespacesAndNewlines), "They are keeping me waiting.")
    }
}
