~ SEED_RANDOM(42)

VAR stringVar = "Initial"
VAR intVar = 0
VAR doubleVar = 0.1
VAR observedVariable = 0

Line 1
-> END

=== Knot1
Move to knot1
-> END

=== Knot2
Knot head text
Lorem ipsum
-> stitch1
= stitch1
You are now at stitch 1
-> END

=== Choice
Choice 1
    * Option 1
    You chose option 1
    * Option 2
    You chose option 2
- -> END

=== Tags
= EmptyTag
Tagtest # testTag
-> END
= ValueTag
Tagtest2 # testTag2: tag2Value
-> END
= RetainTag
This is a retain tag # IMAGE: retain.png
Tag should still be present
-> END
= NonRetainTag
This is a retain tag # nonRetainTag: dontretain.wav
Tag should still not be present
-> END

=== ObservedVariables
~ observedVariable = 1
-> END
