// Typed container paths (ADR-016). Path strings from `.ink.json` are parsed once,
// at the decoder boundary, into these values; `description` reproduces the legacy
// dotted string exactly, because the save format (ADR-018) stays byte-identical.

/// One step of a container path: a child index or a named child.
enum PathComponent: Hashable {
    case index(Int)
    case name(String)

    /// Mirrors C# `Path.componentsString`: integer first, else a name. Only the
    /// canonical spelling of a non-negative integer is an index, so "007", "+5" and
    /// "-1" stay names and every component round-trips through `description`.
    init(parsing string: String) {
        if let index = Int(string), String(index) == string, index >= 0 {
            self = .index(index)
        } else {
            self = .name(string)
        }
    }

    /// "" is no components (the root), not one empty name.
    fileprivate static func components(parsing string: Substring) -> [PathComponent] {
        guard !string.isEmpty else { return [] }
        return string.split(separator: ".", omittingEmptySubsequences: false)
            .map { PathComponent(parsing: String($0)) }
    }
}

extension PathComponent: CustomStringConvertible {
    var description: String {
        switch self {
        case .index(let index): return String(index)
        case .name(let name): return name
        }
    }
}

/// An absolute path from the story root. The only path type accepted as a state
/// key (visit counts, frames, chosen targets), so a relative path never becomes a
/// key. Equality is structural: `knot.0` and `knot.c-0` stay distinct even when
/// they reach the same container.
struct ContainerPath: Hashable {
    let components: [PathComponent]
}

extension ContainerPath: CustomStringConvertible {
    var description: String {
        components.map(\.description).joined(separator: ".")
    }
}

/// A path as written in a node payload: absolute, or relative to the current
/// position. A relative reference stores the raw count of its leading carets; the
/// caret rule (the first caret leaves the object for its container) belongs to the
/// resolver.
enum PathReference: Hashable {
    case absolute(ContainerPath)
    case relative(parentSteps: Int, tail: [PathComponent])

    private static let parent = "^"

    /// Never fails: "" is the root, a leading "." makes the path relative, and the
    /// relative path's leading "^" components are counted. A "^" anywhere else
    /// (inklecate never emits one) is kept as a name, so it still round-trips.
    init(parsing string: String) {
        guard string.hasPrefix(".") else {
            self = .absolute(ContainerPath(components: PathComponent.components(parsing: Substring(string))))
            return
        }
        let components = PathComponent.components(parsing: string.dropFirst())
        let parentSteps = components.prefix { $0 == .name(Self.parent) }.count
        self = .relative(parentSteps: parentSteps, tail: Array(components.dropFirst(parentSteps)))
    }
}

extension PathReference: CustomStringConvertible {
    var description: String {
        switch self {
        case .absolute(let path):
            return path.description
        case .relative(let parentSteps, let tail):
            let parents = Array(repeating: Self.parent, count: parentSteps)
            return "." + (parents + tail.map(\.description)).joined(separator: ".")
        }
    }
}
