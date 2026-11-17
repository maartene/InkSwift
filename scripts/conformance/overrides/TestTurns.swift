let story = try c.compile(0)
for turn in 0..<10 {
    c.equal("\(turn)\n", story.continue())
    try story.chooseChoice(at: 0)
}
