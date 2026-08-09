VAR x = 2
VAR y = 9
VAR calls = 0
~ note(x >= y)
~ note(x != y)
~ x = y >= 1
Calls: {calls}
X: {x}
-> END

=== function note(v) ===
~ calls = calls + 1
