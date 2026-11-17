// conformance-modes: native
// Upstream expects the parse to report a warning.
try c.compile(0, testingErrors: true)
c.isTrue(c.hadWarning())
