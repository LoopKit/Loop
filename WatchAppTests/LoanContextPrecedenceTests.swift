//
//  LoanContextPrecedenceTests.swift
//  WatchAppTests
//
//  During a loan the WATCH is the dosing controller, so the context it authors must outrank the
//  phone's relay of the same reading. `WatchContext.shouldReplace` compares only `glucoseDate`,
//  with `>=`, so a phone context carrying an EQUAL timestamp — which is the normal case, since it
//  is relaying the same physical reading — replaces the watch's and takes its prediction, IOB,
//  COB, temp and loop mode with it.
//
//  This is the intermittent-symptom bug: whether it bites depends on whether a phone context
//  happens to arrive after the watch's, so the prediction goes blank in some cycles and not
//  others. Field 2026-08-16: "it's not always the case the prediction is missing, just certain
//  corner cases."
//
//  These tests pin the PRECEDENCE RULE itself rather than the plumbing around it — that rule is
//  the thing that was wrong, and it is a pure predicate over two contexts.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import WatchApp

final class LoanContextPrecedenceTests: XCTestCase {

    private let unit = LoopUnit.milligramsPerDeciliter

    private func context(glucose: Double, at date: Date, watchAuthored: Bool, eventual: Double? = nil) -> WatchContext {
        let ctx = WatchContext()
        ctx.glucose = LoopQuantity(unit: unit, doubleValue: glucose)
        ctx.glucoseDate = date
        ctx.isWatchAuthored = watchAuthored
        if let eventual {
            ctx.predictedGlucose = WatchPredictedGlucose(values: [
                PredictedGlucoseValue(startDate: date, quantity: LoopQuantity(unit: unit, doubleValue: glucose)),
                PredictedGlucoseValue(startDate: date.addingTimeInterval(.hours(2)),
                                      quantity: LoopQuantity(unit: unit, doubleValue: eventual))
            ])
        }
        return ctx
    }

    /// THE EXACT FIELD CASE: same reading, same timestamp, relayed by the phone a moment after the
    /// watch authored its own. `shouldReplace` says yes — which is why the loan-time refusal in
    /// `updateContext` cannot be expressed as a timestamp comparison.
    func testPhoneContextWithAnEqualTimestampClaimsItShouldReplaceTheWatchs() {
        let t = Date()
        let watch = context(glucose: 143, at: t, watchAuthored: true, eventual: 422)
        let phone = context(glucose: 143, at: t, watchAuthored: false)

        XCTAssertTrue(phone.shouldReplace(watch),
                      "equal glucoseDate replaces under >=, so a loan-time guard is REQUIRED — this is the bug's mechanism")
        XCTAssertFalse(phone.isWatchAuthored)
        XCTAssertTrue(watch.isWatchAuthored)
    }

    /// The flag is the whole basis of the guard, so it must survive nothing and be absent from the
    /// wire: anything arriving from the phone has to read false, whatever the phone did.
    func testWatchAuthoredIsNeverEncodedOntoTheWire() {
        let t = Date()
        let authored = context(glucose: 143, at: t, watchAuthored: true, eventual: 422)
        XCTAssertTrue(authored.isWatchAuthored)

        guard let decoded = WatchContext(rawValue: authored.rawValue) else {
            return XCTFail("a context must survive a rawValue round-trip")
        }
        XCTAssertFalse(decoded.isWatchAuthored,
                       "isWatchAuthored must NOT ride the wire — a phone relay decoding as watch-authored would invert the guard")
    }

    /// What the phone's context would cost if it won: the prediction the wrist just computed.
    func testThePhonesContextCarriesNoPredictionToReplaceTheWatchsWith() {
        let t = Date()
        let watch = context(glucose: 143, at: t, watchAuthored: true, eventual: 422)
        let phone = context(glucose: 143, at: t, watchAuthored: false)

        XCTAssertNotNil(watch.predictedGlucose?.values.last, "the watch's own cycle populates this")
        XCTAssertNil(phone.predictedGlucose,
                     "so letting the phone's win blanks the chart's prediction line — one cause, several symptoms")
    }

    /// Off-loan the ordinary rule still has to hold, or the guard has broken stock behaviour:
    /// a genuinely NEWER phone reading must replace an older one.
    func testANewerPhoneReadingStillReplacesAnOlderContext() {
        let t = Date()
        let older = context(glucose: 143, at: t, watchAuthored: false)
        let newer = context(glucose: 150, at: t.addingTimeInterval(.minutes(5)), watchAuthored: false)

        XCTAssertTrue(newer.shouldReplace(older))
        XCTAssertFalse(older.shouldReplace(newer))
    }
}
