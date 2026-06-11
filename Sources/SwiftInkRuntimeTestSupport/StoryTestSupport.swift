// Test-only extension on Story. Story authors add SwiftInkRuntimeTestSupport
// as a test dependency to access setVisitCount in their own test suites.
@testable import SwiftInkRuntime

public extension Story {
    func setVisitCount(forKnot name: String, to count: Int) {
        engine.setVisitCount(forKnot: name, to: count)
    }
}
