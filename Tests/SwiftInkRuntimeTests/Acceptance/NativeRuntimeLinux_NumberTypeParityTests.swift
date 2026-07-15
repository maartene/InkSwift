// @real-io @adapter-integration
// Feature: native-runtime-linux — US-01 (walking skeleton). KPI-3 guard.
// Adapter: InkDecoder (sole caller of JSON decoding — Rule R3).
//
// These assert that InkDecoder classifies JSON scalars into the SAME NodeKind
// on every platform: a float stays .floatValue, a bool stays .boolValue, and
// neither collapses to .intValue. On macOS they are green today (the current
// CoreFoundation classify path is correct there); they are the regression net
// proving the Linux JSONDecoder swap (ADR-013 / DD-1) preserves macOS typing
// AND makes Linux classify identically. They run on ALL platforms — no
// #if os(macOS) guard — because they depend only on InkDecoder + committed
// literals, never on the macOS-only JS-bridge.
//
// The int case is already covered by
// Milestone1_JSONDecodingTests.`decoder classifies whole numbers as intValue
// not floatValue`; this suite adds the float and bool cases that the
// CoreFoundation CFBoolean/CFNumber path distinguished and that JSONDecoder
// must reproduce.

import Testing
@testable import SwiftInkRuntime

@Suite struct NativeRuntimeLinux_NumberTypeParityTests {

    // GIVEN: an Ink JSON node containing a fractional number
    // WHEN: InkDecoder classifies it
    // THEN: the NodeKind is .floatValue carrying the value — never .intValue

    @Test
    func `decoder classifies a fractional number as floatValue on every platform`() throws {
        let json = #"{"inkVersion":21,"root":[2.5,null],"listDefs":{}}"#
        let data = try #require(json.data(using: .utf8))
        let root = try InkDecoder().decode(data)
        guard case .floatValue(let value) = root.children.first else {
            Issue.record("Expected first child to be .floatValue, got \(String(describing: root.children.first))")
            return
        }
        #expect(value == 2.5)
    }

    // GIVEN: an Ink JSON node containing the boolean `true`
    // WHEN: InkDecoder classifies it
    // THEN: the NodeKind is .boolValue(true) — never .intValue(1)

    @Test
    func `decoder classifies true as boolValue not intValue on every platform`() throws {
        let json = #"{"inkVersion":21,"root":[true,null],"listDefs":{}}"#
        let data = try #require(json.data(using: .utf8))
        let root = try InkDecoder().decode(data)
        guard case .boolValue(let value) = root.children.first else {
            Issue.record("Expected first child to be .boolValue, got \(String(describing: root.children.first))")
            return
        }
        #expect(value == true)
    }

    // GIVEN: an Ink JSON node containing the boolean `false`
    // WHEN: InkDecoder classifies it
    // THEN: the NodeKind is .boolValue(false) — never .intValue(0)

    @Test
    func `decoder classifies false as boolValue not intValue on every platform`() throws {
        let json = #"{"inkVersion":21,"root":[false,null],"listDefs":{}}"#
        let data = try #require(json.data(using: .utf8))
        let root = try InkDecoder().decode(data)
        guard case .boolValue(let value) = root.children.first else {
            Issue.record("Expected first child to be .boolValue, got \(String(describing: root.children.first))")
            return
        }
        #expect(value == false)
    }

    // GIVEN: a whole number and a fractional number in the same container
    // WHEN: InkDecoder classifies them
    // THEN: the whole number is .intValue and the fraction is .floatValue —
    //       the two number kinds never converge

    @Test
    func `decoder keeps integer and float kinds distinct in one container`() throws {
        let json = #"{"inkVersion":21,"root":[42,2.5,null],"listDefs":{}}"#
        let data = try #require(json.data(using: .utf8))
        let root = try InkDecoder().decode(data)
        guard case .intValue(let intValue) = root.children.first else {
            Issue.record("Expected first child to be .intValue, got \(String(describing: root.children.first))")
            return
        }
        guard root.children.count >= 2, case .floatValue(let floatValue) = root.children[1] else {
            Issue.record("Expected second child to be .floatValue, got \(String(describing: root.children.dropFirst().first))")
            return
        }
        #expect(intValue == 42)
        #expect(floatValue == 2.5)
    }
}
