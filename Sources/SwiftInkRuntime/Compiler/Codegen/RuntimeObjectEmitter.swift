// Codegen stage of the native compile pipeline (DDD-10): emit the runtime tree
// (a root `ContainerNode`) the existing runtime plays directly — no JSON
// round-trip (D3). It builds `Decoder/` node types only and never references
// the `Engine/` layer (boundary rule R5).
//
// S0 target: each non-empty source line becomes `.text(line)` followed by
// `.newline`; the root terminates with `.controlCommand("done")`. An empty
// source emits a root containing only `.controlCommand("done")`, so the story
// ends cleanly with no output — mirroring the inklecate oracle's play output.

import Foundation

enum RuntimeObjectEmitter {

    /// Build the runnable root container from parsed source lines.
    static func emitRoot(lines: [String]) -> ContainerNode {
        var children: [NodeKind] = []
        for line in lines {
            children.append(.text(line))
            children.append(.newline)
        }
        children.append(.controlCommand("done"))
        return ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
    }
}
