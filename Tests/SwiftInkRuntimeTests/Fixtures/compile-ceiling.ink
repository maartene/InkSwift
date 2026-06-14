VAR visited = false
VAR force = 2

{visited: Welcome back.|First time here.} #greeting
You have {double(force)} strength.

-> detour ->
The journey continues.

~ raise(force)
Force is now {force}.

{
    - force > 5: You are strong.
    - else: You are weak.
}
-> END

== function double(x) ==
~ return x * 2

== detour ==
A brief detour through the alley.
->->

== function raise(ref n) ==
~ n = n + 1
