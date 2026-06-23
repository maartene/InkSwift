//
//  LineContinuationTests.swift
//  InkSwift
//
//  Created by Engels, Maarten MAK on 23/06/2026.
//

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct LineContinuationTests {
    let inkText =
    """
    VAR trueValue = true

    { trueValue: true text <> }
    should be on the same line

    -> END
    """
    
    @Test func `story evaluates the result into a single line`() throws {
        let blueprint = try InkCompiler.compile(source: inkText)
        let story = Story(blueprint: blueprint)
        
        let text = story.continueMaximally()
        
        #expect(text == "true text should be on the same line\n")
    }
}
