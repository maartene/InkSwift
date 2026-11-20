import Testing
@testable import SwiftInkRuntime

// One catalog of built-in names, behaviour unchanged (ADR-025, step 04-01).
// The token lists below are the decoder's sets as they stood before the
// catalog existed; the catalog must answer for every one of them exactly as
// those sets did.
@Suite struct NativeFunctionCatalogTests {

    static let previouslyAcceptedTokens = [
        "+", "-", "/", "*", "%", "_", "==", ">", "<", ">=", "<=", "!=",
        "!", "&&", "||", "MIN", "MAX", "FLOOR", "CEILING", "INT", "FLOAT",
        "srnd",
    ]

    static let previouslyRefusedTokens: [(token: String, feature: String)] = [
        ("choiceCnt", "CHOICE_COUNT()"),
        ("turn", "TURNS()"),
        ("turns", "TURNS_SINCE()"),
        ("readc", "READ_COUNT() of a divert-target variable"),
        ("rnd", "RANDOM()"),
        ("seq", "shuffle {~a|b}"),
        ("thread", "threads (<-)"),
        ("POW", "POW()"),
        ("?", "? (contains)"),
        ("!?", "!? (does not contain)"),
        ("listInt", "LIST"),
        ("range", "LIST"),
        ("lrnd", "LIST"),
        ("L^", "LIST"),
        ("LIST_MIN", "LIST"),
        ("LIST_MAX", "LIST"),
        ("LIST_ALL", "LIST"),
        ("LIST_COUNT", "LIST"),
        ("LIST_VALUE", "LIST"),
        ("LIST_INVERT", "LIST"),
    ]

    @Test(arguments: previouslyAcceptedTokens)
    func `every token the decoder accepted maps to the supported native with that token`(token: String) {
        let native = NativeFunctionCatalog.supportedNative(forToken: token)
        #expect(native?.token == token)
    }

    @Test func `the supported natives are exactly the tokens the decoder accepted`() {
        #expect(Set(NativeFunction.allCases.map(\.token)) == Set(Self.previouslyAcceptedTokens))
    }

    @Test(arguments: previouslyRefusedTokens)
    func `every refused token yields the same unsupported feature name as before`(token: String, feature: String) {
        #expect(NativeFunctionCatalog.unsupportedFeature(forToken: token) == feature)
    }

    @Test func `the refused tokens are exactly the tokens the decoder refused`() {
        let refused = Set(Self.previouslyRefusedTokens.map(\.token))
        #expect(Set(NativeFunctionCatalog.unsupportedFeatureByToken.keys) == refused)
    }

    @Test(arguments: previouslyAcceptedTokens)
    func `no token is both supported and refused`(token: String) {
        #expect(NativeFunctionCatalog.unsupportedFeature(forToken: token) == nil)
    }

    @Test(arguments: [
        (NativeFunction.add, 2), (.subtract, 2), (.min, 2), (.max, 2), (.equal, 2),
        (.not, 1), (.negate, 1), (.floor, 1), (.ceiling, 1), (.int, 1), (.float, 1),
        (.seedRandom, 1),
    ])
    func `each supported native carries the reference arity`(native: NativeFunction, arity: Int) {
        #expect(NativeFunctionCatalog.entry(for: native).arity == arity)
    }

    @Test func `every two-argument native has a binary operation and no other native does`() {
        let binaryNatives = Set(NativeFunction.allCases.filter { NativeFunctionCatalog.entry(for: $0).arity == 2 })
        #expect(Set(BinaryNativeFunction.byFunction.keys) == binaryNatives)
    }

    @Test func `the binary operation's error name is the catalog token`() {
        for (native, operation) in BinaryNativeFunction.byFunction {
            #expect(operation.function == native)
        }
        #expect(throws: InkRuntimeError(message: "Cannot perform operation 'MIN' on String")) {
            try BinaryNativeFunction.min(.string("a"), .string("b"))
        }
    }

    @Test func `the statement-level constructs carry the runtime's feature names`() {
        #expect(UnsupportedConstruct.thread.name == "threads (<-)")
        #expect(UnsupportedConstruct.list.name == "LIST")
        #expect(UnsupportedConstruct.external.name == "EXTERNAL functions")
        #expect(UnsupportedConstruct.include.name == "INCLUDE")
        #expect(UnsupportedConstruct.shuffle.name == "shuffle {~a|b}")
    }

    @Test func `a native prints as its runtime token`() {
        #expect("\(NativeFunction.min)" == "MIN")
        #expect("\(NativeFunction.negate)" == "_")
    }
}
