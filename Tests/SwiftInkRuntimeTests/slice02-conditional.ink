VAR metCass = false

- (loop)
* {metCass} [Thank you for the coffee.] -> loop
* [Hello for the first time.]
    ~ metCass = true
    -> loop
* [Leave.]
-> END
