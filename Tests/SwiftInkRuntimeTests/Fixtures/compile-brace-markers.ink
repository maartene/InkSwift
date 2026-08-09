VAR a = false

-> start

=== start ===
Once: {!a: x}
Spaced: { !a: q }
OnceBare: {!a}
Cycle: {&a: y}
Seq: {!First|Second}
Escaped: {\!a: NotEscaped|Other}
Cond: {a: yes|no}
ParenNot: {(!a): yes|no}
+ [Again] -> start
+ [Done] -> END
