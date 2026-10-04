//
//  GlanceComplicationTests.swift
//  WatchAppTests
//
//  The glance complication: its snapshot comes from the glance's own sources and formats, each value
//  dashes once it is older than 15 min, and the timeline carries those moments.
//

import XCTest
import LoopKit
import LoopAlgorithm
import LoopCore
@testable import WatchApp

@MainActor
final class GlanceComplicationTests: XCTestCase {

    private let now = Date()

    private func mgdl(_ value: Double) -> LoopQuantity { LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: value) }

    private func glanceData(glucoseAge: TimeInterval = 60, loopAge: TimeInterval = 60, iob: Double? = 2.345,
                            tempRate: Double? = 0.75, closed: Bool = true, overrideLabel: String? = nil) -> WatchLoopManager.GlanceData {
        WatchLoopManager.GlanceData(
            glucose: mgdl(106), glucoseDate: now.addingTimeInterval(-glucoseAge),
            directG7At: now.addingTimeInterval(-glucoseAge), phoneRelayAt: nil, sensorActivatedAt: nil,
            trend: .up, eventual: mgdl(112.4), iob: iob,
            dosingEventual: nil, dosingIOB: nil, dosingCOB: nil,
            tempRate: tempRate, lastLoopCompleted: now.addingTimeInterval(-loopAge),
            suspendThreshold: mgdl(70), closedLoopEnabled: closed,
            recommendedTempRate: nil, lastLoopErrorText: nil, predictionBreakdown: nil,
            retrospectiveCorrectionIsIntegral: false, retrospectiveDiscrepancyCount: 0,
            overrideLabel: overrideLabel)
    }

    // MARK: - Sources

    /// During a loan the numbers are the glance's own strings, so the two can never disagree.
    func testALoanPublishesTheGlancesOwnNumbers() {
        let data = glanceData(overrideLabel: "🏃 70% 140")
        let glance = GlanceViewModel.activeState(data: data, cob: 15.4, now: now)
        let s = GlanceComplicationPublisher.snapshot(loan: data, cob: 15.4, unit: .milligramsPerDeciliter, now: now)

        XCTAssertEqual(s.iobText, glance.iobText)
        XCTAssertEqual(s.cobText, glance.cobText)
        XCTAssertEqual(s.tempText, glance.tempText)
        XCTAssertEqual(s.overrideLabel, glance.overrideLabel)
        XCTAssertEqual(s.bg(at: now), glance.bgText)
        XCTAssertEqual(s.trend(at: now), glance.trendSymbol)
        XCTAssertEqual(s.eventual(at: now), glance.eventualText)
        XCTAssertEqual(s.bgRange, .inRange)
        XCTAssertTrue(s.watchHasPod)
    }

    /// A value the loop has not produced is a dash, not the glance's placeholder string.
    func testAMissingLoanValueIsADash() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(iob: nil, tempRate: nil), cob: nil,
                                                     unit: .milligramsPerDeciliter, now: now)
        XCTAssertEqual(s.line(.iobCob, at: now), "IOB — · COB —")
        XCTAssertEqual(s.value(.temp, at: now), "—")
    }

    /// Outside a loan: the phone's context, formatted as the glance formats, and its override.
    func testThePhonesContextIsFormattedAsTheGlance() {
        let context = WatchContext(glucose: mgdl(173), displayGlucoseUnit: .milligramsPerDeciliter, glucoseTrend: .flat,
                                   glucoseDate: now.addingTimeInterval(-60), loopLastRunDate: now.addingTimeInterval(-120),
                                   lastNetTempBasalDose: -0.4, cob: 22.6, iob: 0.04, isClosedLoop: true)
        let override = TemporaryScheduleOverride(context: .custom,
                                                 settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                                   insulinNeedsScaleFactor: 0.7),
                                                 startDate: now.addingTimeInterval(-600), duration: .indefinite,
                                                 enactTrigger: .local, syncIdentifier: UUID())
        let s = GlanceComplicationPublisher.snapshot(phone: context, override: override)

        XCTAssertEqual(s.line(.bg, at: now), "BG 173→")
        XCTAssertEqual(s.line(.iobCob, at: now), "IOB 0.0 · COB 23")
        XCTAssertEqual(s.value(.temp, at: now), "-0.40")
        XCTAssertEqual(s.overrideLabel, "⏱ 70%")
        XCTAssertNil(s.bgRange, "the glance does not vouch for the phone's reading")
        XCTAssertFalse(s.watchHasPod)
    }

    // MARK: - Staleness

    /// As stock's complication: a reading older than 15 min shows a dash, and so does the eventual.
    func testAStaleReadingDashesWithItsEventual() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(glucoseAge: 16 * 60), cob: 10,
                                                     unit: .milligramsPerDeciliter, now: now)
        XCTAssertEqual(s.line(.bgEventual, at: now), "— → —")
        XCTAssertNotNil(s.iob(at: now), "the loop's values stand on their own clock")
    }

    /// A frozen IOB on a face with no ring would be read as current; past 15 min it dashes.
    func testTheLoopsValuesDashWhenItsCycleIsOld() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(loopAge: 15.5 * 60), cob: 10,
                                                     unit: .milligramsPerDeciliter, now: now)
        XCTAssertEqual(s.line(.iobCob, at: now), "IOB — · COB —")
        XCTAssertEqual(s.value(.temp, at: now), "—")
        XCTAssertEqual(s.freshness(at: now), .aging)
    }

    /// Stock's HUD: an open loop always reads fresh, and its ring never schedules a change.
    func testAnOpenLoopRingReadsFresh() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(loopAge: 20 * 60, closed: false), cob: nil,
                                                     unit: .milligramsPerDeciliter, now: now)
        XCTAssertEqual(s.freshness(at: now), .fresh)
    }

    func testTheTimelineMarksEachChangeMoment() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(glucoseAge: 30, loopAge: 120), cob: 10,
                                                     unit: .milligramsPerDeciliter, now: now)
        let moments = s.changeMoments(after: now)
        XCTAssertEqual(moments.count, 4, "loop aging, loop values stale, loop stale, reading stale")
        XCTAssertEqual(s.freshness(at: moments[0]), .aging, "4 min: the ring turns")
        XCTAssertNil(s.iob(at: moments[1]), "13 min: the cycle's values dash")
        XCTAssertNotNil(s.bg(at: moments[1]))
        XCTAssertEqual(s.freshness(at: moments[2]), .stale, "14 min: the ring goes red")
        XCTAssertNil(s.bg(at: moments[3]), "14.5 min: the reading dashes")
    }

    // MARK: - Catalogue

    /// Every metric is offered in the face editor, each with its own name.
    func testEveryMetricIsRecommended() {
        let titles = GlanceMetric.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, GlanceMetric.allCases.count)
        XCTAssertEqual(GlanceMetric.allCases.count, 10)
    }

    func testTheSnapshotRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "GlanceComplicationTests")!
        defaults.removePersistentDomain(forName: "GlanceComplicationTests")
        let s = GlanceComplicationSnapshot.sample
        s.save(to: defaults)
        XCTAssertEqual(GlanceComplicationSnapshot.load(from: defaults), s)
    }

    /// The confirmation runs count what the widget served, read back by the app.
    func testServedTimelinesAreReadBackAfterADate() {
        let defaults = UserDefaults(suiteName: "GlanceComplicationServed")!
        defaults.removePersistentDomain(forName: "GlanceComplicationServed")
        GlanceComplicationSnapshot.noteServed("iob", at: now.addingTimeInterval(-120), defaults: defaults)
        GlanceComplicationSnapshot.noteServed("bg", at: now.addingTimeInterval(-30), defaults: defaults)
        let served = GlanceComplicationSnapshot.served(after: now.addingTimeInterval(-60), defaults: defaults)
        XCTAssertEqual(served.map(\.metric), ["bg"])
    }

    /// The loop's age reads in whole minutes, with a timeline mark at each, and stops counting at 30.
    func testTheLoopAgeCountsWholeMinutes() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(loopAge: 30), cob: 10,
                                                     unit: .milligramsPerDeciliter, now: now)
        XCTAssertEqual(s.loopAge(at: now), "now")
        XCTAssertEqual(s.loopAge(at: now.addingTimeInterval(4 * 60)), "4m")
        XCTAssertEqual(s.loopAge(at: now.addingTimeInterval(45 * 60)), "30m+")
        let marks = s.loopAgeMarks(after: now)
        XCTAssertEqual(marks.count, 30)
        XCTAssertEqual(s.loopAge(at: marks[0]), "1m")
    }

    /// A rectangle shows its value large and BG → eventual beneath, or the loop's numbers under BG.
    func testARectangleCarriesContext() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(), cob: 15, unit: .milligramsPerDeciliter, now: now)
        let up = GlucoseTrend.up.symbol
        XCTAssertEqual(s.headline(.iob, at: now), "2.3")
        XCTAssertEqual(s.context(.iob, at: now), "106\(up) → 112")
        XCTAssertEqual(s.headline(.bg, at: now), "106\(up)")
        XCTAssertEqual(s.context(.bg, at: now), "IOB 2.3 · COB 15")
    }

    /// A circle shows an override as its symbol over the rest of the label.
    func testAnOverrideSplitsForACircle() {
        var s = GlanceComplicationSnapshot()
        XCTAssertEqual(s.overrideParts.symbol, "—")
        s.overrideLabel = "🏃 70% 140"
        XCTAssertEqual(s.overrideParts.symbol, "🏃")
        XCTAssertEqual(s.overrideParts.rest, "70% 140")
        s.overrideLabel = "⏱"
        XCTAssertEqual(s.overrideParts.rest, "")
    }
}
