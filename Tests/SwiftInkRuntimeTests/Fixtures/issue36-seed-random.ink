// Issue #36: SEED_RANDOM pops its seed and pushes void, as the reference does
// (Story.cs, SeedRandom), so the pop compiled for the discarded call removes
// that void and nothing else. The seed is called while `1 +` waits on the
// evaluation stack; an unbalanced pop takes the 1 and the sum goes wrong.
// The sum sits alone on its line: inklecate's JSON puts a newline after the
// call inside `seeded`, which InkSwift does not yet trim mid-line (conformance:
// implicit inline glue around function calls).
~ SEED_RANDOM(5)
{1 + seeded()}
After the seed.
* Keep going
    The choice played.
    -> END

=== function seeded()
~ SEED_RANDOM(7)
~ return 2
