// conformance-modes: native
// Upstream compiles one story per identifier character range, using every
// character of the range as the identifier (`string.Format`).
for range in UpstreamCharacterRanges.all {
    let identifier = range.identifier
    try c.compile(source: """
        CONST \(identifier)pi = 3.1415
        CONST \(identifier)a = "World"
        CONST \(identifier)b = 3
        """, testingErrors: true)
    if c.errorMessages.count > 0 {
        c.fail("\(range.name): \(c.errorMessages.all)")
    }
}
