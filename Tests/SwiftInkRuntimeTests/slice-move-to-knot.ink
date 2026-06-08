// Fixture for native-move-to-knot acceptance tests.
// Entry point: with_choices — leaves story at a choice point after one continue(),
// giving a "dirty" mid-execution state for jump tests.
VAR score = 0

-> with_choices

=== with_choices ===
You are at a crossroads.
* [Option A]
    You chose A.
    -> END
* [Option B]
    You chose B.
    -> END

// Jump to this knot to set score = 42 before jumping to epilogue.
=== score_setup ===
~ score = 42
Your score is set.
-> END

=== prologue ===
Once upon a time there was a detective.
-> END

=== interrogation ===
Detective Mills enters the room.
-> END

=== epilogue ===
The final score was {score}.
-> END

=== investigation ===
You begin investigating.
-> investigation.lab

= lab
The lab is full of evidence.
-> END
