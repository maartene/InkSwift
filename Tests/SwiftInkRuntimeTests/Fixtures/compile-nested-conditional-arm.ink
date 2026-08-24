VAR x = 2
VAR y = 1

-> outer_else_arm

=== outer_else_arm ===
Before nesting.
{ x == 3:
    Three.
- else:
    { x == 1:
        One.
    - else:
        Two.
    }
}
After nesting.
* [Continue]
    -> outer_true_arm

=== outer_true_arm ===
Before second nesting.
{ y == 1:
    { x == 2:
        Nested in the true arm.
    - else:
        Not two.
    }
- else:
    Other.
}
After second nesting.
-> END
