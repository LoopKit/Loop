//
//  ComplicationSnapshotTests.swift
//  LoopTests
//
//  The watch complications' snapshot (compiled into this target from Loop Complications): what shows at
//  each moment, the timeline's change moments, and when the watch app asks WidgetKit to reload.
//

import XCTest

final class ComplicationSnapshotTests: XCTestCase {

    private let now = Date()

    private func snapshot(glucoseAge: TimeInterval = 60, loopAge: TimeInterval = 60) -> ComplicationSnapshot {
        let reading = now.addingTimeInterval(-glucoseAge)
        let loop = now.addingTimeInterval(-loopAge)
        return ComplicationSnapshot(glucoseText: "106", trendSymbol: "↗", staleGlucoseText: "---",
                                    glucoseStaleAt: reading.addingTimeInterval(15 * 60), eventualText: "108",
                                    inlineText: "106↗ 108 8:47 PM", inlineStaleText: "--- 108 8:47 PM",
                                    loopDate: loop, freshUntil: loop.addingTimeInterval(6 * 60),
                                    agingUntil: loop.addingTimeInterval(16 * 60), graphRenderedAt: nil)
    }

    func testAFreshReadingShowsWithItsTrend() {
        let s = snapshot()
        XCTAssertEqual(s.glucose(at: now), "106")
        XCTAssertEqual(s.trend(at: now), "↗")
        XCTAssertEqual(s.inline(at: now), "106↗ 108 8:47 PM")
    }

    /// As the ClockKit templates: a stale reading shows the stale marker and drops the trend.
    func testAStaleReadingShowsTheMarkerAndNoTrend() {
        let s = snapshot(glucoseAge: 16 * 60)
        XCTAssertEqual(s.glucose(at: now), "---")
        XCTAssertEqual(s.trend(at: now), "")
        XCTAssertEqual(s.inline(at: now), "--- 108 8:47 PM")
    }

    func testLoopFreshnessFollowsTheLoopsAge() {
        XCTAssertEqual(snapshot(loopAge: 60).freshness(at: now), .fresh)
        XCTAssertEqual(snapshot(loopAge: 10 * 60).freshness(at: now), .aging)
        XCTAssertEqual(snapshot(loopAge: 20 * 60).freshness(at: now), .stale)
        var noLoop = snapshot()
        noLoop.loopDate = nil
        XCTAssertEqual(noLoop.freshness(at: now), .stale)
    }

    /// The timeline carries the moments things change on their own, so none of them needs a reload.
    func testTheTimelineMarksEachChangeMoment() {
        let s = snapshot(glucoseAge: 60, loopAge: 60)
        let moments = s.changeMoments(after: now)
        XCTAssertEqual(moments.count, 3, "reading stale, loop aging, loop stale")
        XCTAssertEqual(s.freshness(at: moments[0]), .aging, "first: the loop turns at 6 min")
        XCTAssertTrue(s.glucoseIsStale(at: moments[1]), "then the reading at 15 min")
        XCTAssertEqual(s.freshness(at: moments[2]), .stale, "then the loop at 16 min")
    }

    func testTheSnapshotRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "ComplicationSnapshotTests")!
        defaults.removePersistentDomain(forName: "ComplicationSnapshotTests")
        snapshot().save(to: defaults)
        XCTAssertEqual(ComplicationSnapshot.load(from: defaults), snapshot())
    }

    /// Reloads are budgeted: at most one per window, and a change inside the window is not lost.
    func testReloadsAreThrottledButNeverLost() {
        var throttle = ComplicationReloadThrottle<ComplicationSnapshot>()
        let a = snapshot(), b = snapshot(glucoseAge: 0)

        XCTAssertEqual(throttle.offer(a, now: now).reload, true, "the first value reloads at once")
        let unchanged = throttle.offer(a, now: now.addingTimeInterval(60))
        XCTAssertFalse(unchanged.save, "an unchanged value is not rewritten")
        XCTAssertFalse(unchanged.reload)
        let early = throttle.offer(b, now: now.addingTimeInterval(120))
        XCTAssertTrue(early.save)
        XCTAssertFalse(early.reload, "inside the window: saved, reload owed")
        XCTAssertTrue(throttle.offer(b, now: now.addingTimeInterval(301)).reload, "the owed reload is paid once the window passes")
        XCTAssertFalse(throttle.offer(b, now: now.addingTimeInterval(700)).reload, "nothing owed, nothing reloaded")
    }
}
