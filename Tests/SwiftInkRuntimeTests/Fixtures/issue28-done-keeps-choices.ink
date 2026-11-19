// #28 counterpart: `-> DONE` in the same shape keeps the pending choice, and
// choosing it plays its content and what follows.
VAR x = 0
Before the block.
{ x == 0:
    Inside the arm.
    * A choice that DONE keeps
        Chosen content.
        -> after
}
After the block.
-> DONE

=== after ===
After the choice.
* Onward
    Last line.
    -> END
