// conformance-modes: native
// Upstream parses `*` and expects exactly one warning, and no errors.
try c.compile(0, testingErrors: true)
c.equal(0, c.errorMessages.count)
c.equal(1, c.warningMessages.count)
c.isTrue(c.warningMessages[safe: 0].contains("completely empty"))
