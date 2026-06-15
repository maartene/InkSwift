VAR turns = 0
-> hub

=== hub ===
You arrive at the hub.
- {&The torch gutters.|The torch steadies.} {!A draft stirs.|The air is still.}
    + [Open the left door] You take the left door.
    + [Open the right door] You take the right door.
    - ~ turns = turns + 1
    {turns < 2: -> hub}
    -> END
