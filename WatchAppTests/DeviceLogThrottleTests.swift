//
//  DeviceLogThrottleTests.swift
//  WatchAppTests
//
//  The device-log storm guard, tested for the first time. It was four fields and a lock inline
//  on WatchLoopManager, reachable only by driving a real CGM or pump manager's delegate — so the
//  thing that protects the log during an incident had never been exercised outside one.
//
//  Its failure modes are both quiet and both bad: throttle too little and a retry storm starves
//  MAIN and rotates the evidence out of the log; throttle too much and lines vanish with no
//  record that anything was dropped.
//

import XCTest
@testable import WatchApp

final class DeviceLogThrottleTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - The basic contract

    func testFirstLineIsAlwaysWrittenWithNothingToFlush() {
        let throttle = DeviceLogThrottle()
        XCTAssertEqual(throttle.admit("connect failed", at: t0), .write(flushing: 0))
    }

    func testDistinctLinesPassThroughUntouched() {
        let throttle = DeviceLogThrottle()
        XCTAssertEqual(throttle.admit("a", at: t0), .write(flushing: 0))
        XCTAssertEqual(throttle.admit("b", at: t0), .write(flushing: 0),
                       "a different line is never suppressed, even at the same instant")
        XCTAssertEqual(throttle.admit("c", at: t0), .write(flushing: 0))
    }

    func testIdenticalLineInsideTheWindowIsSuppressed() {
        let throttle = DeviceLogThrottle()
        _ = throttle.admit("Code=11", at: t0)
        XCTAssertEqual(throttle.admit("Code=11", at: t0.addingTimeInterval(0.5)), .suppress)
    }

    func testIdenticalLineAfterTheWindowIsWrittenAgain() {
        let throttle = DeviceLogThrottle()
        _ = throttle.admit("Code=11", at: t0)
        XCTAssertEqual(throttle.admit("Code=11", at: t0.addingTimeInterval(2.0)), .write(flushing: 0),
                       "the window is exclusive — at exactly 2.0 s the line writes again")
    }

    // MARK: - The count must not be lost

    /// The property that makes suppression honest. A suppressed run is only acceptable because
    /// the NEXT line states how many were dropped; without this the log has a silent hole
    /// exactly where the storm was.
    func testSuppressedCountIsFlushedOntoTheNextDifferentLine() {
        let throttle = DeviceLogThrottle()
        _ = throttle.admit("storm", at: t0)
        for i in 1...5 {
            XCTAssertEqual(throttle.admit("storm", at: t0.addingTimeInterval(Double(i) * 0.1)), .suppress)
        }
        XCTAssertEqual(throttle.admit("something else", at: t0.addingTimeInterval(0.7)),
                       .write(flushing: 5), "all five suppressed repeats are reported, not lost")
    }

    func testCountResetsAfterBeingFlushed() {
        let throttle = DeviceLogThrottle()
        _ = throttle.admit("x", at: t0)
        _ = throttle.admit("x", at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(throttle.admit("y", at: t0.addingTimeInterval(0.2)), .write(flushing: 1))
        XCTAssertEqual(throttle.admit("z", at: t0.addingTimeInterval(0.3)), .write(flushing: 0),
                       "the count is consumed by the flush, not carried forward")
    }

    /// A run that ends by TIMING OUT rather than by a different line still reports its count.
    func testCountIsFlushedWhenTheSameLineReturnsAfterTheWindow() {
        let throttle = DeviceLogThrottle()
        _ = throttle.admit("x", at: t0)
        _ = throttle.admit("x", at: t0.addingTimeInterval(0.5))
        _ = throttle.admit("x", at: t0.addingTimeInterval(1.0))
        XCTAssertEqual(throttle.admit("x", at: t0.addingTimeInterval(3.5)), .write(flushing: 2),
                       "the run ended by timing out; its count still has to surface")
    }

    // MARK: - The storm shape

    /// The window SLIDES on every repeat, so a sustained storm stays collapsed instead of
    /// punching a line through every 2 s. This is what keeps a 2,000-line/second loop cheap.
    func testASustainedStormStaysCollapsedRatherThanLeakingEvery2Seconds() {
        let throttle = DeviceLogThrottle()
        _ = throttle.admit("Code=11", at: t0)
        var suppressed = 0
        // 10 seconds of repeats at 100/s — five windows' worth if the window did NOT slide.
        for i in 1...1000 {
            if throttle.admit("Code=11", at: t0.addingTimeInterval(Double(i) * 0.01)) == .suppress {
                suppressed += 1
            }
        }
        XCTAssertEqual(suppressed, 1000, "every repeat inside a sliding window is collapsed")
        XCTAssertEqual(throttle.admit("recovered", at: t0.addingTimeInterval(10.1)),
                       .write(flushing: 1000), "and the whole storm is accounted for in one line")
    }

    /// Two devices interleaving must not suppress each other — the delegate is shared by the CGM
    /// and pump managers, so alternating lines are the normal case, not an edge case.
    func testAlternatingLinesFromTwoDevicesAreNeverSuppressed() {
        let throttle = DeviceLogThrottle()
        for i in 0..<20 {
            let line = i.isMultiple(of: 2) ? "cgm connect" : "pod connect"
            XCTAssertEqual(throttle.admit(line, at: t0.addingTimeInterval(Double(i) * 0.01)),
                           .write(flushing: 0), "alternating lines are all distinct from their predecessor")
        }
    }

    // MARK: - Concurrency

    /// Called from whichever queue the CGM or pump manager happens to be on, and during a storm
    /// from several at once. Every admit must be accounted for exactly once.
    func testConcurrentAdmitsAreAccountedForExactlyOnce() {
        let throttle = DeviceLogThrottle()
        let iterations = 500
        let counter = NSLock()
        var writes = 0, suppresses = 0

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let verdict = throttle.admit("same line", at: self.t0)
            counter.lock()
            if case .write = verdict { writes += 1 } else { suppresses += 1 }
            counter.unlock()
        }

        XCTAssertEqual(writes + suppresses, iterations, "no admit was lost or double-counted")
        XCTAssertEqual(writes, 1, "identical lines at one instant: exactly one wins the write")
    }
}
