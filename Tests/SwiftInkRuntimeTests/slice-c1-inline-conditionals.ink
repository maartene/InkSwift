VAR metCass = false

-> start

=== start ===
You enter the café.
* [You see a stranger.]
    -> check
* [You see your friend.]
    ~ metCass = true
    -> check

=== check ===
{metCass: You know her.|She's a stranger.}
-> END
