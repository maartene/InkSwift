// Issue #28, synthetic: a knot entered by a top-level divert whose flat body
// runs out after a line of prose, with nothing on the call stack. The reference
// (Story.cs ContinueInternal ~502-516) reports "ran out of content. Do you
// need a '-> DONE' or '-> END'?" once the prose has played.
Before the knot.
-> somewhere

== somewhere ==
Inside the knot.
