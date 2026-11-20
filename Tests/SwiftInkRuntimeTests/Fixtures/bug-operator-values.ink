VAR b = true
VAR z = 0.0
H: {-b} {FLOOR(b)} {not b} {INT(b)} {FLOAT(b)}
I: {CEILING(b)}
C: {1.0 / z} {-1.0 / z} {0.0 / z} {1.0 % z}
J: {INT(1.0 / z)} {INT(-1.0 / z)} {INT(0.0 / z)}
After.
* Go
    Gone.
    -> END
