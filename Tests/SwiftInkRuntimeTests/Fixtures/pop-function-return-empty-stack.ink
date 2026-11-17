// `~ return` with an EMPTY call stack: a top-level variable divert into a
// function (a plain `-> f` is rejected by inklecate: "f can't be diverted to").
// Functions may not contain choices, and nothing follows a divert at the top
// level, so the continuation is the prose after the return.
VAR target = -> f
Before the divert.
-> target

== function f ==
Inside f.
~ return
After the return.
