// conformance-modes: native
// Upstream runs inklecate's CommentEliminator directly; InkSwift's counterpart
// is `CommentEliminator.strip`.
let content = "A// C\nA /* C */ A\n\nA * A * /* * C *// A/*\nC C C\n\n*/"
c.equal("A\nA  A\n\nA * A * / A\n\n\n", CommentEliminator.strip(content))
