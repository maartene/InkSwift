VAR x = 2

-> binary_arms

=== binary_arms ===
{ x == 2:
- Binary true arm.
- Binary false arm.
}
After the true binary.
{ x == 1:
- Not taken true arm.
- Taken false arm.
}
After the false binary.
{ x == 1:
- Lone arm under a false header.
}
After the lone arm.
{ x == 2:
- Two words: the colon stays in the true arm.
- Two words: the colon stays in the false arm.
}
After the colon content.
{
- x == 1: Guarded one.
- : Empty guard is content.
}
After the empty guard.
{ x:
- 1: Switch one.
- Switch fallback.
}
After the colon-less switch fallback.
* [Continue]
    -> finale

=== finale ===
After the choice.
-> END
