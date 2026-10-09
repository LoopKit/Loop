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
        XCTAssertEqual(s.bgRange, .inRange, "coloured as during a loan; the icon says who holds the pod")
        XCTAssertFalse(s.watchHasPod)

        // The phone's suspend threshold sets the low line, as the glance's own rule; 180 the high one.
        let low = WatchContext(glucose: mgdl(78), displayGlucoseUnit: .milligramsPerDeciliter, glucoseTrend: .flat,
                               glucoseDate: now.addingTimeInterval(-60), loopLastRunDate: now.addingTimeInterval(-120),
                               lastNetTempBasalDose: 0, cob: 0, iob: 0, isClosedLoop: true)
        XCTAssertEqual(GlanceComplicationPublisher.snapshot(phone: low, override: nil, suspendThreshold: mgdl(80)).bgRange, .low)
        XCTAssertEqual(GlanceComplicationPublisher.snapshot(phone: low, override: nil).bgRange, .inRange, "70 when unknown")
        XCTAssertEqual(GlanceComplicationPublisher.range(mgdl: 181, suspendThreshold: nil), .high)
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
        XCTAssertEqual(GlanceMetric.allCases.count, 11)
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
        XCTAssertEqual(s.headline(.bigBG, at: now), "106\(up)", "Big BG is the reading and its trend alone")
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

    /// A reload is served within a second of the publish that asked for it: still counted.
    func testATimelineServedInTheSameSecondIsCounted() {
        let defaults = UserDefaults(suiteName: "GlanceComplicationServedSubsecond")!
        defaults.removePersistentDomain(forName: "GlanceComplicationServedSubsecond")
        let publish = Date(timeIntervalSince1970: 1_000_000.4)
        GlanceComplicationSnapshot.noteServed("bigBG", at: publish.addingTimeInterval(0.5), defaults: defaults)
        XCTAssertEqual(GlanceComplicationSnapshot.served(after: publish, defaults: defaults).map(\.metric), ["bigBG"])
    }

    /// Big BG's age counts from the reading, and goes with it once the reading dashes.
    func testTheReadingsAgeCountsFromTheReading() {
        let s = GlanceComplicationPublisher.snapshot(loan: glanceData(glucoseAge: 130), cob: 10,
                                                     unit: .milligramsPerDeciliter, now: now)
        XCTAssertEqual(s.bgAge(at: now), "2m")
        XCTAssertEqual(s.bgAge(at: now.addingTimeInterval(16 * 60)), "")
        XCTAssertEqual(s.bgAgeMarks(after: now).first, s.bgDate?.addingTimeInterval(3 * 60))
    }

    // MARK: - Redraw rule

    private func reading(_ mgdl: Double, trend: String = "→", holder: Bool = false, takenAgo: TimeInterval = 0,
                         iob: String = "1.0", at base: Date? = nil) -> GlanceComplicationSnapshot {
        var s = GlanceComplicationSnapshot()
        s.bgText = String(Int(mgdl))
        s.trendSymbol = trend
        s.bgDate = (base ?? now).addingTimeInterval(-takenAgo)
        s.bgStaleAt = s.bgDate?.addingTimeInterval(15 * 60)
        s.iobText = iob
        s.watchHasPod = holder
        return s
    }

    private func offset(_ d: Date?, from base: Date) -> TimeInterval { d.map { $0.timeIntervalSince(base) } ?? -1 }

    /// A reading goes just after its link settles when the last confirmed request is 300.1 s back.
    func testAReadingGoesWhenItsLinkSettles() {
        var policy = GlanceReloadPolicy()
        _ = policy.save(reading(100), at: now.addingTimeInterval(0.4))
        let plan = policy.plan(now: now.addingTimeInterval(0.4), inFront: false, opened: false, sensorLinkUp: now,
                               inLoan: false, lastRenderAt: now.addingTimeInterval(-400))
        XCTAssertEqual(offset(plan?.at, from: now), 1.2, accuracy: 0.001)
    }

    /// An early reading waits inside its link to be 300.1 s after the last confirmed request.
    func testAnEarlyReadingWaitsInsideItsLink() {
        var policy = GlanceReloadPolicy()
        policy.confirmed(at: now.addingTimeInterval(1.2), attached: true)
        let early = now.addingTimeInterval(298.5)
        _ = policy.save(reading(103, at: early), at: early.addingTimeInterval(0.3))
        let plan = policy.plan(now: early.addingTimeInterval(0.3), inFront: false, opened: false, sensorLinkUp: early,
                               inLoan: false, lastRenderAt: now.addingTimeInterval(1.5))
        XCTAssertEqual(offset(plan?.at, from: early), 2.8, accuracy: 0.001, "1.2 + 300.1 - 298.5")
    }

    /// Off a loan the link is the only connected window: a reading too early for it waits for the next one.
    func testOffALoanAReadingTooEarlyForItsLinkWaits() {
        var policy = GlanceReloadPolicy()
        policy.confirmed(at: now.addingTimeInterval(1.2), attached: true)
        let early = now.addingTimeInterval(296.0)
        _ = policy.save(reading(99, at: early), at: early.addingTimeInterval(0.3))
        XCTAssertNil(policy.plan(now: early.addingTimeInterval(0.3), inFront: false, opened: false, sensorLinkUp: early,
                                 inLoan: false, lastRenderAt: now.addingTimeInterval(1.5)))
    }

    /// In a loan the pod exchange after the reading is a second connected window.
    func testInALoanThePodExchangeIsASecondWindow() {
        var policy = GlanceReloadPolicy()
        policy.confirmed(at: now.addingTimeInterval(1.2), attached: true)
        let early = now.addingTimeInterval(296.0)
        _ = policy.save(reading(99, at: early), at: early.addingTimeInterval(9))
        let plan = policy.plan(now: early.addingTimeInterval(9), inFront: false, opened: false, sensorLinkUp: early,
                               inLoan: true, lastRenderAt: now.addingTimeInterval(1.5))
        XCTAssertEqual(offset(plan?.at, from: early), 9.0, accuracy: 0.001)
    }

    /// Only a connected, built request starts the period: a draw from opening the app while disconnected doesn't.
    func testOnlyAConfirmedConnectedRequestStartsThePeriod() {
        var policy = GlanceReloadPolicy()
        policy.confirmed(at: now.addingTimeInterval(1.2), attached: true)
        policy.confirmed(at: now.addingTimeInterval(120), attached: false)       // foreground draw
        let next = now.addingTimeInterval(300.5)
        _ = policy.save(reading(110, at: next), at: next.addingTimeInterval(0.3))
        let plan = policy.plan(now: next.addingTimeInterval(0.3), inFront: false, opened: false, sensorLinkUp: next,
                               inLoan: false, lastRenderAt: now.addingTimeInterval(120.5))
        XCTAssertEqual(offset(plan?.at, from: next), 1.2, accuracy: 0.001)
    }

    /// A change outside this cycle's windows waits for the next reading instead of spending its slot.
    func testAChangeBetweenReadingsWaits() {
        var policy = GlanceReloadPolicy()
        _ = policy.save(reading(100, iob: "2.0"), at: now.addingTimeInterval(120))
        XCTAssertNil(policy.plan(now: now.addingTimeInterval(120), inFront: false, opened: false, sensorLinkUp: now,
                                 inLoan: true, lastRenderAt: now.addingTimeInterval(2)))
        XCTAssertTrue(policy.behind(lastRenderAt: now.addingTimeInterval(2)))
    }

    /// In front, only a reading the face hasn't built is requested: opening the app with a current face
    /// leaves the slot alone, and a face stuck on an old reading is caught up whatever we asked before.
    func testInFrontOnlyAnUnbuiltReadingIsRequested() {
        var policy = GlanceReloadPolicy()
        _ = policy.save(reading(100), at: now)
        _ = policy.save(reading(100, iob: "2.0"), at: now.addingTimeInterval(30))
        XCTAssertNil(policy.plan(now: now.addingTimeInterval(60), inFront: true, opened: true, sensorLinkUp: now,
                                 inLoan: false, lastRenderAt: now.addingTimeInterval(2)))
        _ = policy.save(reading(108, at: now.addingTimeInterval(300)), at: now.addingTimeInterval(301))
        XCTAssertEqual(policy.plan(now: now.addingTimeInterval(320), inFront: true, opened: true, sensorLinkUp: now,
                                   inLoan: false, lastRenderAt: now.addingTimeInterval(2))?.reason, "opened")
    }

    /// Connected by timing: the link's first seconds and, in a loan, the pod exchange; not the gap after.
    func testAttachedFollowsTheLinkAndThePodExchange() {
        XCTAssertTrue(GlanceReloadPolicy.attached(at: now.addingTimeInterval(2), sensorLinkUp: now, inLoan: false))
        XCTAssertFalse(GlanceReloadPolicy.attached(at: now.addingTimeInterval(9), sensorLinkUp: now, inLoan: false))
        XCTAssertTrue(GlanceReloadPolicy.attached(at: now.addingTimeInterval(9), sensorLinkUp: now, inLoan: true))
        XCTAssertFalse(GlanceReloadPolicy.attached(at: now.addingTimeInterval(36), sensorLinkUp: now, inLoan: true))
    }
}
