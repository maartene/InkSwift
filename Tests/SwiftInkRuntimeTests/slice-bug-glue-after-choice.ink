VAR cooperate = false
VAR tellme = true

Opening line.
-> waited

=== waited
- Two cups of tea on the table.
    *    {tellme} [Deny] "I'm not pretending anything."
        {cooperate:I'm lying already.}
        Harris looks disapproving. -> pushes_cup
    *    (took) [Take one]
        I take a mug and warm my hands. It's <>
    *    (what2) {not tellme} "What's going on?"
        "You know already."
        -> pushes_cup
    *    [Wait]
        I wait for him to speak.
        - - (pushes_cup) He pushes one mug halfway towards me: <>
- a small gesture of friendship.
Enough to give me hope?
-> END
