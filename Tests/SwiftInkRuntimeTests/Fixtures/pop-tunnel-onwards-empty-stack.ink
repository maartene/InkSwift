// `->->` with an EMPTY call stack: a top-level plain divert into a knot that
// tunnels onwards.
Before the divert.
-> g

== g ==
Inside g.
->->
After the tunnel onwards.
* Continue from g
    -> END

== elsewhere ==
Somewhere else.
* Leave
    -> END
