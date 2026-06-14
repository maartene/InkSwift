// Secondary Ink-JSON sink (D4): serialise the runtime tree (a `ContainerNode`
// produced by `RuntimeObjectEmitter`) into Ink-JSON text for Level-2
// structural-oracle comparison, caching, and interop. Lower priority than the
// primary no-round-trip tree path (D3).
//
// Boundary rules:
//   R3 — uses deterministic manual string building only (the Foundation
//        serialiser reserved for Decoder/ is off-limits here); the produced
//        text mirrors the Ink-JSON shape that `Decoder/InkDecoder.swift` READS
//        (text as "^...", "\n" for newline, bare control-command strings,
//        top-level {"inkVersion":21,"root":[...],"listDefs":{}}).
//   R5 — constructs/reads `Decoder/` node types only; never imports `Engine/`.

import Foundation

enum JSONEmitter {

    /// Ink-JSON runtime format version emitted (matches the runtime's reader,
    /// which accepts inkVersion >= 20).
    private static let inkVersion = 21

    /// Serialise a runtime root container into Ink-JSON text.
    static func emit(root: ContainerNode) -> String {
        let rootArray = serializeContainerContents(root)
        return "{\"inkVersion\":\(inkVersion),\"root\":\(rootArray),\"listDefs\":{}}"
    }

    /// Serialise a container's content as a JSON array. The trailing metadata
    /// slot (flags/name/named-content) is emitted as `null` for the S0 shape,
    /// mirroring what `InkDecoder.parseContainer` tolerates as "no metadata".
    private static func serializeContainerContents(_ container: ContainerNode) -> String {
        let elements = container.children.map(serializeNode)
        let joined = (elements + ["null"]).joined(separator: ",")
        return "[\(joined)]"
    }

    /// Serialise a single node to its Ink-JSON token.
    private static func serializeNode(_ node: NodeKind) -> String {
        switch node {
        case .text(let value):
            return jsonString("^" + value)
        case .newline:
            return jsonString("\n")
        case .controlCommand(let command):
            return jsonString(command)
        case .container(let sub):
            return serializeContainerContents(sub)
        default:
            // S0 scope emits only text/newline/done; richer nodes land in later
            // slices. A void token keeps the array well-formed in the interim.
            return jsonString("void")
        }
    }

    /// Encode a Swift string as a JSON string literal (quoted, escaped).
    private static func jsonString(_ raw: String) -> String {
        var escaped = ""
        for character in raw {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }
}
