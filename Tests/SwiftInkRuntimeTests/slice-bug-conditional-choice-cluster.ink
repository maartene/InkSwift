VAR drugged = false

~ drugged = true

{ not drugged:
    A.
- else:
    B.
}
Q?
* [Always]
* { drugged } [Only if drugged]
- -> END
