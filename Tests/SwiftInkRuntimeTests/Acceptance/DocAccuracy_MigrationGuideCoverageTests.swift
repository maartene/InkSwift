// @us-03
//
// US-03 — Migration guide maps InkStory to the native API.
//
// Doc-accuracy guard: the migration guide at docs/how-to/migrate-from-js-bridge.md
// must cover 100% of the InkStory public API. This suite parses
// Sources/InkSwift/InkStory.swift as TEXT (NOT `import InkSwift` — platform-neutral,
// runs on Linux CI) for every public func/var/init member declared on the InkStory
// type, and asserts each member's identifier appears somewhere in the guide markdown.
//
// The public surface deliberately includes the typo'd `oberservedVariables`, plus
// `retainTags`, `registerObservedVariable`, and `deregisterObservedVariable`; the
// observation members are covered as the no-native-equivalent gap.
//
// Reuses DocAccuracySupport (repo-root + parser) from
// DocAccuracy_ParityStatementConsistencyTests.swift (same test target).

import Testing
import Foundation

@Suite("Doc Accuracy — Migration guide covers 100% of the InkStory public API (US-03)")
struct DocAccuracy_MigrationGuideCoverageTests {

    @Test func `every public InkStory member is mapped in the migration guide`() throws {
        let source = try DocAccuracySupport.contents(of: "Sources/InkSwift/InkStory.swift")
        let guide = try DocAccuracySupport.contents(of: "docs/how-to/migrate-from-js-bridge.md")

        let members = DocAccuracySupport.publicMembers(ofType: "InkStory", inSwiftSource: source)
        #expect(members.isEmpty == false, "sanity: the parser must find InkStory public members")

        for member in members.sorted() {
            #expect(
                guide.contains(member),
                "migration guide must map the InkStory public member '\(member)'"
            )
        }
    }
}
