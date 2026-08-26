VAR x = 1
VAR y = 9

-> true_arm_at_depth

=== true_arm_at_depth ===
Before the first weave.
* First
    Chose first.
    { x == 1:
        * * From the nested true arm
            -> else_arm_at_depth
    }
    After the block in first.
* Second
    -> else_arm_at_depth

=== else_arm_at_depth ===
Before the second weave.
* Outer
    Chose outer.
    { y == 2:
        Two.
    - else:
        * * From the nested else arm
            -> done
    }
    After the block in outer.

=== done ===
Done.
-> END
