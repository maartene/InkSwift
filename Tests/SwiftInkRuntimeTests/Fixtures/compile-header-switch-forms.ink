VAR x = 2
VAR flag = true

-> header_switches

=== header_switches ===
{ x == 1:
- true: Bool true arm.
- false: Bool false arm.
}
After the boolean switch.
{ x == 1:
- true: Bool true with else.
- else: Bool else arm.
}
After the boolean switch with else.
{ x != 1:
- false: Not-equal false arm.
- true: Not-equal true arm.
}
After the not-equal switch.
{ x > 1 and x < 3:
- true: Compound true arm.
- else: Compound else arm.
}
After the compound switch.
{ flag:
- else: Flag else arm.
}
After the else-only block.
{ x:
- 1: Value one.
- 2: Value two.
- else: Value other.
}
After the value switch.
* [Continue]
    -> arithmetic

=== arithmetic ===
{ x * 2:
- 4: Four.
- else: Not four.
}
After the arithmetic switch.
-> END
