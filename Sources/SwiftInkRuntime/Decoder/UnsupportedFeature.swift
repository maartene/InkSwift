import Foundation

/// An ink feature a compiled story uses that the runtime does not support yet,
/// reported by `Story(json:)` as `StoryError.unsupportedFeatures` (issue #32).
///
/// The runtime refuses such a story at load, for the whole story, instead of
/// playing on with the feature printed as text or skipped: a feature in a
/// rarely visited knot would otherwise surprise a player late, and be hard to
/// trace. Knowing at load lets the author change the ink, or play this story
/// on the JS-bridge (`InkStory`).
public struct UnsupportedFeature: Equatable, Sendable {
    /// The feature as an author knows it, e.g. `"LIST"`, `"threads (<-)"`,
    /// `"RANDOM()"`, `"shuffle {~a|b}"`, `"TURNS_SINCE()"`.
    public let name: String
    /// Where the story uses it: knot, stitch and label paths such as `"shop"`
    /// or `"shop.haggle"`, sorted; `""` is the top level, outside any knot.
    public let locations: [String]

    public init(name: String, locations: [String]) {
        self.name = name
        self.locations = locations
    }
}

/// Collects the unsupported features found while decoding, with the
/// author-visible location of each.
struct UnsupportedFeatureLog {
    private var locationsByFeature: [String: Set<String>] = [:]

    var isEmpty: Bool { locationsByFeature.isEmpty }

    mutating func record(_ feature: String, at location: [String]) {
        locationsByFeature[feature, default: []].insert(location.joined(separator: "."))
    }

    /// One entry per feature, sorted by name, each with its sorted locations.
    var features: [UnsupportedFeature] {
        locationsByFeature
            .map { UnsupportedFeature(name: $0.key, locations: $0.value.sorted()) }
            .sorted { $0.name < $1.name }
    }

    /// `location` extended by a container's `name`, when that is a name the
    /// author wrote (a knot, stitch or label) rather than one inklecate
    /// generated: `c-0`/`g-0` (choices, gathers), `b` (a branch), `s` (choice
    /// text), `s0`, `s1`… (sequence elements), `$r…` (return points), `global decl`.
    static func location(_ location: [String], entering name: String?) -> [String] {
        guard let name, isAuthorName(name), location.last != name else { return location }
        return location + [name]
    }

    private static func isAuthorName(_ name: String) -> Bool {
        if ["b", "s", "global decl"].contains(name) || name.hasPrefix("$") { return false }
        if Int(name) != nil { return false }
        if name.first == "s", Int(name.dropFirst()) != nil { return false }
        let generated = name.split(separator: "-", maxSplits: 1)
        if generated.count == 2, ["c", "g"].contains(generated[0]), Int(generated[1]) != nil {
            return false
        }
        return true
    }
}
