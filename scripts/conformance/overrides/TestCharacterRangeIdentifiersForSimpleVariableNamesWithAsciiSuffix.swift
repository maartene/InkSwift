// conformance-modes: native
// Upstream compiles one story per identifier character range, using every
// character of the range as the identifier (`string.Format`).
for range in UpstreamCharacterRanges.all {
    let identifier = range.identifier
    try c.compile(source: """
        VAR \(identifier)pi = 3.1415
        VAR \(identifier)a = "World"
        VAR \(identifier)b = 3
        """, testingErrors: true)
    if c.errorMessages.count > 0 {
        c.fail("\(range.name): \(c.errorMessages.all)")
    }
}
