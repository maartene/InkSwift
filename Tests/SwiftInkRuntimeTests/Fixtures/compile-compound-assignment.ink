VAR counter = 10
~ counter += 5
After plus: {counter}
~ counter -= 3
After minus: {counter}
* [Increase in choice]
    ~ counter += 100
    Choice counter: {counter}
- -> END
