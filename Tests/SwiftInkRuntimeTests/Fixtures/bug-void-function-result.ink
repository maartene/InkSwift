VAR saved = 1
~ temp q = 5
A {q} {implicit()} B
C {q} {bare()} D
~ temp x = implicit()
E {q}{x} F
~ saved = bare()
G {q}{saved} H
After.
* Go
    Gone {saved}.
    I {q}{saved} J
    -> END

== function implicit
~ temp z = 1
== function bare
~ return
