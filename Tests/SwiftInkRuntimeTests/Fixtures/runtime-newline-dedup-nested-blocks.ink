VAR x = 2
{ x > 0:
    { x == 2:
        Inner.
    }
}
After the nested block.
{ x > 0:
    Outer.
    { x == 1:
        A.
    - else:
        B.
    }
    After the inner block.
- else:
    C.
}
After the outer block.
* Onward
    Chosen.
    -> END
