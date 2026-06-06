VAR score = 0
VAR outcome = 0

-> start

=== start ===
You are being evaluated.
* [Easy quiz.]
    ~ score = 5
    -> score_check
* [Hard quiz.]
    ~ score = 15
    -> score_check
* [Get caught.]
    ~ outcome = 1
    -> outcome_check
* [Slip away.]
    ~ outcome = 2
    -> outcome_check
* [Disappear.]
    ~ outcome = 99
    -> outcome_check

=== score_check ===
{ score > 10:
    You passed.
- else:
    You failed.
}
-> END

=== outcome_check ===
{ outcome:
- 1: Arrested.
- 2: Escaped.
- else: Unknown.
}
-> END
