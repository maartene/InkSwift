// conformance-modes: native
// Upstream compiles one story per identifier character range, using every
// character of the range as the identifier (`string.Format`).
for range in UpstreamCharacterRanges.all {
    let identifier = range.identifier
    try c.compile(source: """
        VAR \(identifier)z = -> \(identifier)divert
        
        == \(identifier)divert ==
        -> END
        """, testingErrors: true)
    if c.errorMessages.count > 0 {
        // The identifier spans the whole range (thousands of characters for CJK and
        // Korean); name it instead, so the failure message stays short and readable.
        let errors = c.errorMessages.all.map { $0.replacingOccurrences(of: identifier, with: "<\(range.name)>") }
        c.fail("\(range.name): \(errors)")
    }
}
