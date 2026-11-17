let story = try c.compile(0)
let globalTags = ["author: Joe", "title: My Great Story"]
let knotTags = ["knot tag"]
c.equal(globalTags, story.globalTags)
c.equal("This is the content\n", story.continue())
c.equal(globalTags, story.currentTags)
// Upstream also expects `TagsForContentAtPath("knot")` to be ["knot tag"] and
// `TagsForContentAtPath("knot.stitch")` to be ["stitch tag"].
c.fail("needs a TagsForContentAtPath API")
try story.choosePath("knot")
c.equal("Knot content\n", story.continue())
c.equal(knotTags, story.currentTags)
c.equal("", story.continue())
c.equal(["end of knot tag"], story.currentTags)
