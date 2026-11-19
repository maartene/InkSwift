VAR n = 0
VAR m = 0
VAR target = -> by_variable
-> hub

== hub ==
Hub {hub}.
- (round)
~ n++
Round {round}.
{n < 3: -> round}
After the rounds, round {round}.
-> rooms.east
= back
Back in hub {hub}, back {back}.
-> finale
= finale
Finale {hub} {finale}.
-> loop_knot

== rooms ==
Rooms {rooms}.
-> west
= east
East {rooms} {east}.
-> west
= west
West {rooms} {west}.
{west < 2: -> east}
-> hub.back

== loop_knot ==
~ m++
Loop knot {loop_knot}.
{m < 3: -> loop_knot}
-> tunnels

== tunnels ==
-> pass_through ->
-> pass_through ->
Passed {pass_through}.
-> inner ->
-> inner ->
Inner {inner}, tunnels {tunnels}.
-> calls
= inner
In the inner stitch {inner}.
->->

== pass_through ==
Passing {pass_through}.
->->

== calls ==
~ twice()
~ twice()
Called {twice}.
-> target
= after_variable
After variable {by_variable}.
Prose after the diverts.
* Finish
  Finished.
  -> END

== function twice ==
~ return

== by_variable ==
By variable {by_variable}.
~ target = -> var_knot.spot
-> target

== var_knot ==
Var knot body.
-> DONE
= spot
Spot {var_knot} {var_knot.spot}.
-> calls.after_variable
