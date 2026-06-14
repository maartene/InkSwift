-> start

=== function double(n) ===
~ return n * 2

VAR sideEffect = false

=== function setSideEffect() ===
~ sideEffect = true

=== start ===
You enter.
* [Calculate inline.]
    The result is {double(5)}.
    -> END
* [Calculate and store.]
    ~ temp result = double(7)
    Stored: {result}.
    -> END
* [Void call inline.]
    {setSideEffect()}
    Done.
    -> END
