VAR a = true
VAR b = false
~ temp andWord = a and b
~ temp orWord = a or b
~ temp mixedWordSymbol = a and not b
~ temp mixedSymbolBang = a && !b
AndWord: {andWord}
OrWord: {orWord}
MixedWordSymbol: {mixedWordSymbol}
MixedSymbolBang: {mixedSymbolBang}
* [Choice guarded by word-form and] {a and not b}
    Guard passed: {a and not b}
- -> END
