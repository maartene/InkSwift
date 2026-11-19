// #28 / inkle/ink#978: a choice generated earlier in the same continue is
// discarded when the flow reaches `-> END` (C# ForceEnd clears the choices).
VAR x = 0
Before the block.
{ x == 0:
    Inside the arm.
    * A choice that END discards
        Chosen content.
        -> after
}
After the block.
-> END

=== after ===
After the choice.
* Onward
    Never reached by the END variant.
    -> END
