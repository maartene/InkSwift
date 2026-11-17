let story = try c.compile(0)
c.equal("else\nelse\nhi\n", story.continueMaximally())
c.equal(0, story.engine.state.evalStack.count)
