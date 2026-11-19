LIST colours = red, green
VAR c = red
Top: {POW(2, 2)}.
-> shop
== shop
Welcome.
* [Haggle] -> shop.haggle
* [Leave] -> END
= haggle
Price: {RANDOM(1, 9)}. {c}
Mood: {&calm {RANDOM(1, 3)}|cross}.
-> END
== never_visited
<- shop
~ temp r = RANDOM(1, 2)
-> END
