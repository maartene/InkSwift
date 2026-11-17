// `~ return` while a TUNNEL frame is on top of the call stack. inklecate rejects
// a plain `-> f` into a function ("f can't be diverted to"), but allows a divert
// target value, so the tunnel body reaches f through a variable divert.
// Functions may not contain choices, so the choice of the continuation sits in
// the caller, after the tunnel, where a popped tunnel frame would resume.
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
~ return
After the return.
