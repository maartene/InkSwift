// Step 04-04 (ADR-025 §5): POW and the string contains operators play as
// inklecate plays them. POW of two ints is a float (C# `(float)Math.Pow`).
// `?` / `has` and `!?` / `hasnt` bind tighter than comparison and looser than
// addition, left to right (InkParser_Expressions.cs, precedence 3): the
// precedence line reads ("ab" + "c") ? "bc", ("ab" ? "b") == true and
// ("a" ? "a") ? "true". A non-string operand on the other side is cast to a
// string, so "a5b" ? 5 is true. Content follows the operators, then a choice.
POW: {POW(2, 3)} and {POW(2, 0.5)}.
Contains: {"hello" ? "xyz": yes|no} {"hello" !? "xyz": yes|no} {"hello" ? "ell": yes|no}.
Words: {"hello" has "ell": yes|no} {"hello" hasnt "ell": yes|no}.
Precedence: {"ab" + "c" ? "bc"} {"ab" ? "b" == true} {"a" ? "a" ? "true"}.
Coerced: {"a5b" ? 5}.
After the operators.
* Keep going
    The choice played.
    -> END
