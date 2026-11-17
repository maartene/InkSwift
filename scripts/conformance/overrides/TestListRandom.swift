let story = try c.compile(0)
while story.canContinue {
    c.isTrue(["B\n", "C\n", "D\n"].contains(story.continue()))
}
