//
//  BooleanConditionsTests.swift
//  InkSwift
//
//  Created by Engels, Maarten MAK on 23/06/2026.
//

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct BooleanConditionsTests {
    let inkText =
    """
    VAR trueValue = true
    VAR boolean = false

    { trueValue && boolean: true text }
    { trueValue && boolean == false: false text }

    -> END
    """
    
    @Test func `story evaluates complex boolean expression correctly`() throws {
        let blueprint = try InkCompiler.compile(source: inkText)
        let story = Story(blueprint: blueprint)
        
        let text = story.continueMaximally()
        
        #expect(text == "false text\n")
    }
}
