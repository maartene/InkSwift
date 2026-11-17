// conformance-modes: native
let content = "A B\nC D // comment\nA B\r\nC D // comment\r\n/* block comment\r\nsecond line\r\n */ "
c.equal("A B\nC D \nA B\nC D \n\n\n ", CommentEliminator.strip(content))
