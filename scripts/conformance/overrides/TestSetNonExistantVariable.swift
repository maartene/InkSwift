let story = try c.compile(0)
c.equal("Hello world.\n", story.continue())
// Upstream expects setting an undeclared variable to throw. InkSwift's
// `setVariable(_:to:)` is non-throwing; the observable counterpart is that the
// variable is not created (undecided, see #27).
story.setVariable("y", to: "earth")
c.isNil(story.getVariable("y"))
