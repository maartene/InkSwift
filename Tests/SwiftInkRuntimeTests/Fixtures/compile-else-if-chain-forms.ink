VAR x = 2

-> headerless_chain

=== headerless_chain ===
Before the chain.
{
- x == 1:
    One.
- x == 2:
    Two.
- else:
    Other.
}
After the chain.
* [Continue]
    -> header_with_else

=== header_with_else ===
Before the if-else.
{ x == 1:
    One.
- else:
    Not one.
}
After the if-else.
-> END
