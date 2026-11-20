// Issue #36: natively compiled built-ins must play as inklecate does.
// Each line used to compile to an unresolved call that left a function frame
// on the stack and printed its last argument. Content follows the calls so a
// frame that never pops, or a flow that stops, shows up in the playthrough.
{FLOOR(1.5)}
{INT(1.7)}
{CEILING(1.2)}
{FLOAT(1) / 2}
{FLOAT(2)}
{MIN(1, 2)}
{MAX(1, 2)}
{CEILING(1.2) / 3}
After the built-ins.
* Keep going
    The choice played.
    -> END
