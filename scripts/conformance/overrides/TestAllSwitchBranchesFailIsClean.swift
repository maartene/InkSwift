let story = try c.compile(0)
story.continue()
c.equal(0, story.engine.state.evalStack.count)
