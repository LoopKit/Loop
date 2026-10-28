//
//  LoanContextPrecedenceTests.swift
//  WatchAppTests
//
//  What the screens show (`LoopDataManager.displayContext(phone:wrist:directGlucose:)`): during a
//  loan the watch's state over the phone's context, whatever the phone's context says; otherwise the
//  phone's, with the watch's own reading when it is newer. The active override follows the same rule
//  (`LoopDataManager.scheduleOverride(phone:wrist:)`).
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import WatchApp

final class LoanContextPrecedenceTests: XCTestCase {

    private let unit = LoopUnit.milligramsPerDeciliter

    private func context(glucose: Double, at date: Date, eventual: Double? = nil) -> WatchContext {
        let ctx = WatchContext()
        ctx.glucose = LoopQuantity(unit: unit, doubleValue: glucose)
        ctx.glucoseDate = date
        if let eventual {
            ctx.predictedGlucose = WatchPredictedGlucose(values: [
                PredictedGlucoseValue(startDate: date, quantity: LoopQuantity(unit: unit, doubleValue: glucose)),
                PredictedGlucoseValue(startDate: date.addingTimeInterval(.hours(2)),
                                      quantity: LoopQuantity(unit: unit, doubleValue: eventual))
            ])
        }
        return ctx
    }

    private func reading(_ glucose: Double, at date: Date) -> NewGlucoseSample {
        NewGlucoseSample(date: date, quantity: LoopQuantity(unit: unit, doubleValue: glucose), condition: nil,
                         trend: .flat, trendRate: nil, isDisplayOnly: false, wasUserEntered: false,
                         syncIdentifier: UUID().uuidString)
    }

    /// The phone's relay of the same reading (equal timestamp, no prediction) cannot blank the watch's
    /// prediction: the watch's state is laid over whatever the phone's context is.
    func testDuringALoanThePhonesContextCannotReplaceTheWatchsPrediction() {
        let t = Date()
        let phone = context(glucose: 143, at: t)
        let wrist = context(glucose: 143, at: t, eventual: 422)

        let shown = LoopDataManager.displayContext(phone: phone, wrist: wrist, directGlucose: nil)
        XCTAssertEqual(shown?.eventualGlucose?.doubleValue(for: unit), 422)
    }

    /// Nothing of the phone's dosing state survives a loan; what only the phone knows carries through.
    func testDuringALoanThePhonesDosingStateGoesAndItsDisplayUnitStays() {
        let t = Date()
        let phone = WatchContext(glucose: LoopQuantity(unit: unit, doubleValue: 120), displayGlucoseUnit: unit)
        phone.glucoseDate = t
        phone.iob = 3.2
        phone.recommendedBolusDose = 1.5
        let wrist = context(glucose: 95, at: t, eventual: 110)
        wrist.iob = 1.1

        let shown = LoopDataManager.displayContext(phone: phone, wrist: wrist, directGlucose: nil)
        XCTAssertEqual(shown?.glucose?.doubleValue(for: unit), 95)
        XCTAssertEqual(shown?.iob, 1.1)
        XCTAssertNil(shown?.recommendedBolusDose)
        XCTAssertEqual(shown?.displayGlucoseUnit, unit)
    }

    /// Without a loan the watch's own reading shows only while it is newer than the phone's.
    func testWithoutALoanTheWatchsOwnReadingShowsOnlyWhenNewer() {
        let t = Date()
        let phone = context(glucose: 143, at: t)

        let newer = LoopDataManager.displayContext(phone: phone, wrist: nil, directGlucose: reading(150, at: t.addingTimeInterval(.minutes(5))))
        XCTAssertEqual(newer?.glucose?.doubleValue(for: unit), 150)

        let older = LoopDataManager.displayContext(phone: phone, wrist: nil, directGlucose: reading(130, at: t.addingTimeInterval(.minutes(-5))))
        XCTAssertEqual(older?.glucose?.doubleValue(for: unit), 143)
    }

    /// Stock's rule between phone contexts still holds: a newer reading replaces an older one.
    func testANewerPhoneReadingStillReplacesAnOlderContext() {
        let t = Date()
        let older = context(glucose: 143, at: t)
        let newer = context(glucose: 150, at: t.addingTimeInterval(.minutes(5)))

        XCTAssertTrue(newer.shouldReplace(older))
        XCTAssertFalse(older.shouldReplace(newer))
    }

    private func override(needs scale: Double) -> TemporaryScheduleOverride {
        TemporaryScheduleOverride(context: .custom,
                                  settings: TemporaryPresetSettings(unit: unit, targetRange: nil, insulinNeedsScaleFactor: scale),
                                  startDate: Date(), duration: .indefinite, enactTrigger: .local, syncIdentifier: UUID())
    }

    /// During a loan the screens show the override the watch's loop doses with, whatever the phone's
    /// settings say; between loans, the phone's.
    func testDuringALoanTheScreensShowTheLoopsOverride() {
        let phone = override(needs: 0.5)
        let watch = override(needs: 1.2)

        XCTAssertEqual(LoopDataManager.scheduleOverride(phone: phone, wrist: .some(watch)), watch)
        XCTAssertNil(LoopDataManager.scheduleOverride(phone: phone, wrist: .some(nil)), "a loan with no override shows none")
        XCTAssertEqual(LoopDataManager.scheduleOverride(phone: phone, wrist: .none), phone, "between loans, the phone's")
    }
}
