//
//  CompilerTests.swift
//  
//
//  Created by Maarten Engels on 17/05/2022.
//

import XCTest
@testable import InkSwift

final class CompilerTests: XCTestCase {
    
    func testCompileHelloWorld() {
        print("For now this test always succeeds as the Ink compiler is not yet a strandard part of InkJS.")
        XCTAssert(true)
        
//        let inkStory = InkStory()
//        inkStory.loadStory(ink: "Hello, World")
//        print(inkStory.currentText)
    }
    
    static var allTests = [
        ("testCompileHelloWorld", testCompileHelloWorld)
    ]
}
