// Upstream builds C# `Path` objects; InkSwift parses the same strings into
// `PathReference` (ADR-016), whose relative and absolute forms are distinct
// cases — so `.hello.1.world` can never equal `hello.1.world`.
let path1 = PathReference(parsing: "hello.1.world")
let path2 = PathReference(parsing: "hello.1.world")

let path3 = PathReference(parsing: ".hello.1.world")
let path4 = PathReference(parsing: ".hello.1.world")

c.equal(path1, path2)

c.equal(path3, path4)

c.notEqual(path1, path3)
