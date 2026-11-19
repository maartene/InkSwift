VAR x = 0
Start of the story.
* [Run out after the knot's gather] -> knot_gather
* [Run out of choices in the knot] -> knot_choices
* [Run out of choices after a block] -> knot_rejoin
* [Stay at the top]
    Stayed at the top.
- Root gather.
The root ends here.

=== knot_gather ===
In the knot.
* [Take the knot's choice]
    Took the knot's choice.
- Gathered in the knot.
The knot runs out here.

=== knot_choices ===
Visiting the knot.
* [Take the once-only choice]
    Took the once-only choice.
- Gathered before revisiting.
-> knot_choices

=== knot_rejoin ===
Visiting the rejoin knot.
{ x == 0:
    In the block.
}
After the block.
* [Take the choice after the block]
    Took the choice after the block.
- Gathered after the block.
-> knot_rejoin
