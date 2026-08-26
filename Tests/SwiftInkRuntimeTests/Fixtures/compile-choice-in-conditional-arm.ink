VAR x = 1
VAR y = 2

-> else_arm

=== else_arm ===
Before the else arm.
{ x == 0:
    Zero.
    * From the zero arm
        -> implicit_true_arm
- else:
    Other.
    * From the else arm
        -> implicit_true_arm
}
After the else block.

=== implicit_true_arm ===
Before the true arm.
{ x == 1:
    One.
    * From the true arm
        -> middle_arm
}
After the true block.

=== middle_arm ===
Before the middle arm.
{
    - y == 1:
        One.
    - y == 2:
        Two.
        * From the middle arm
            -> done
    - else:
        Other.
}
After the middle block.

=== done ===
Done.
-> END
