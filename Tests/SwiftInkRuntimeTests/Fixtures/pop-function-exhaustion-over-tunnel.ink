// A function body that runs out (no `~ return`) while a TUNNEL frame is on top
// of the call stack: the tunnel body reaches f through a variable divert (a
// plain `-> f` is rejected by inklecate). Functions may not contain choices, so
// the choice of the continuation sits in the caller, after the tunnel, where a
// consumed tunnel frame would resume.
VAR target = -> f
Before the tunnel.
-> t ->
After the tunnel.
* Continue from the root
    -> END

== t ==
Inside the tunnel.
-> target

== function f ==
Inside f.
