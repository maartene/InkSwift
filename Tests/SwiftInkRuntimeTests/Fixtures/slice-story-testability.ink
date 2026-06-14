VAR score = 0
VAR badge_awarded = false
VAR player_name = "unnamed"
VAR has_key = false

-> start

=== start ===
Hello, {player_name}.
-> DONE

=== score_setup ===
~ score = 42
Score is set.
-> DONE

=== reward_check ===
{ score >= 10:
    You earned the gold badge.
    ~ badge_awarded = true
- else:
    You did not earn the badge.
}
-> DONE

=== locked_door ===
{ has_key:
    The door swings open.
- else:
    You need a key.
}
-> DONE

=== greeting ===
{ prologue > 1:
    Welcome back!
- else:
    Hello, stranger.
}
-> DONE

=== prologue ===
Once upon a time.
-> DONE

=== multi_line ===
Line one.
Line two.
Line three.
-> DONE

=== with_choices ===
At the crossroads.
* [Go left.] -> left
* [Go right.] -> right

=== left ===
You went left.
-> DONE

=== right ===
You went right.
-> DONE
