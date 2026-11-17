// `->->` while a FUNCTION frame is on top of the call stack. inklecate rejects a
// divert inside a function (FlowBase.cs: "Functions may not contain diverts"),
// so the function itself states the tunnel onwards. Functions may not contain
// choices either, so the choice of the continuation sits in the caller, after
// the call, where an engine that walked on or popped the frame would resume.
Before the call.
~ temp result = f()
After the call.
* Continue from the root
    -> END

== function f ==
Inside f.
->->
After the tunnel onwards.
~ return 1
