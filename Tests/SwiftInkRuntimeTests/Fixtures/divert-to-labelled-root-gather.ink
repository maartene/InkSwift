// A divert into a labelled root gather whose choices are all hidden: the
// labelled container sits in the root weave's content array, so once it runs
// out the flow falls out into its parent and reaches the root's `done`
// (C# Story.cs IncrementContentPointer). inklecate -p ends cleanly here.
VAR left = false
Start of the story.
- (top)
* {not left} [Stay at the top]
    Stayed at the top.
* {not left} [Use up the top's choices] -> leave
- Root gather.
The root ends here.

=== leave ===
Leaving the top.
~ left = true
-> top
