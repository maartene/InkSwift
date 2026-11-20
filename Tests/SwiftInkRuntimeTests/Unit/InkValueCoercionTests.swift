// #37 part 2 / ADR-024 — the one operand-coercion point and the cast result
// types, at value level. C# order: bool < int < float < string (Value.cs
// ValueType); the coerced type is never below int (NativeFunctionCall.cs
// CoerceValuesToSingleType starts from Int).

import Testing
@testable import SwiftInkRuntime

@Suite struct InkValueCoercionTests {

    struct Pair: CustomTestStringConvertible, Sendable {
        let lhs: InkValue
        let rhs: InkValue
        let coerced: CoercedOperands
        var testDescription: String { "\(lhs) with \(rhs)" }
    }

    static let pairs = [
        Pair(lhs: .bool(true), rhs: .bool(false), coerced: .ints(1, 0)),
        Pair(lhs: .bool(true), rhs: .int(2), coerced: .ints(1, 2)),
        Pair(lhs: .bool(true), rhs: .float(2.5), coerced: .floats(1.0, 2.5)),
        Pair(lhs: .bool(false), rhs: .string("a"), coerced: .strings("false", "a")),
        Pair(lhs: .int(1), rhs: .float(2.5), coerced: .floats(1.0, 2.5)),
        Pair(lhs: .int(1), rhs: .string("a"), coerced: .strings("1", "a")),
        Pair(lhs: .float(1.5), rhs: .string("a"), coerced: .strings("1.5", "a")),
    ]

    @Test(arguments: pairs)
    func `both operands coerce to the higher type in either order`(pair: Pair) {
        #expect(InkValue.coerced(pair.lhs, pair.rhs) == pair.coerced)

        let swapped: CoercedOperands = switch pair.coerced {
        case .ints(let a, let b): .ints(b, a)
        case .floats(let a, let b): .floats(b, a)
        case .strings(let a, let b): .strings(b, a)
        }
        #expect(InkValue.coerced(pair.rhs, pair.lhs) == swapped)
    }

    @Test func `a float operand prints in its 32-bit form when coerced to a string`() {
        #expect(InkValue.coerced(.float(0.1 + 0.2), .string("")) == .strings("0.3", ""))
    }

    @Test(arguments: [
        (InkValue.float(1.5), InkValue.float(1.0), InkValue.float(2.0)),
        (InkValue.float(-1.5), InkValue.float(-2.0), InkValue.float(-1.0)),
        (InkValue.int(3), InkValue.int(3), InkValue.int(3)),
    ])
    func `FLOOR and CEILING keep a float a float and an int an int`(
        value: InkValue, floor: InkValue, ceiling: InkValue
    ) {
        #expect(value.floored == floor)
        #expect(value.ceiled == ceiling)
    }

    @Test(arguments: [
        (InkValue.float(1.7), InkValue.int(1)),
        (InkValue.float(-1.7), InkValue.int(-1)),
        (InkValue.int(4), InkValue.int(4)),
    ])
    func `INT truncates a float to an int and keeps an int`(value: InkValue, expected: InkValue) {
        #expect(value.toInt == expected)
    }

    @Test func `FLOAT of an int is a float`() {
        #expect(InkValue.int(2).toFloat == .float(2.0))
    }
}
