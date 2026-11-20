VAR s = "a"
VAR z = 0
Before.
* [not s] -> not_string
* [negate s] -> negate_string
* [FLOOR s] -> floor_string
* [CEILING s] -> ceiling_string
* [INT s] -> int_string
* [FLOAT s] -> float_string
* [int divide by zero] -> divide_by_zero
* [int modulo by zero] -> modulo_by_zero
* [void plus one] -> void_binary
* [negate void] -> void_unary

=== not_string
{not s}
After not.
-> after

=== negate_string
{-s}
After negate.
-> after

=== floor_string
{FLOOR(s)}
After FLOOR.
-> after

=== ceiling_string
{CEILING(s)}
After CEILING.
-> after

=== int_string
{INT(s)}
After INT.
-> after

=== float_string
{FLOAT(s)}
After FLOAT.
-> after

=== divide_by_zero
{1 / z}
After divide.
-> after

=== modulo_by_zero
{7 % z}
After modulo.
-> after

=== void_binary
{nothing() + 1}
After void plus one.
-> after

=== void_unary
{-nothing()}
After negate void.
-> after

=== after
After.
* Go
    Gone.
    -> END

== function nothing
~ temp unused = 1
