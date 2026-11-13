//
//  GlucoseStatisticsTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopKitUI
@testable import Loop

final class GlucoseStatisticsTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // 2026-01-01 00:00:00 UTC
    private var midnight: Date { cal.date(from: DateComponents(year: 2026, month: 1, day: 1))! }

    private func sample(_ mgdl: Double, at date: Date,
                        isDisplayOnly: Bool = false, wasUserEntered: Bool = false) -> StoredGlucoseSample {
        StoredGlucoseSample(startDate: date, quantity: .glucose(value: mgdl),
                            isDisplayOnly: isDisplayOnly, wasUserEntered: wasUserEntered)
    }

    // MARK: - Percentile helper

    func testPercentileInterpolation() {
        let v = [10.0, 20, 30, 40, 50]
        XCTAssertEqual(GlucoseStatistics.percentile(v, 0.5), 30, accuracy: 1e-9)
        XCTAssertEqual(GlucoseStatistics.percentile(v, 0.25), 20, accuracy: 1e-9)
        XCTAssertEqual(GlucoseStatistics.percentile(v, 0.05), 12, accuracy: 1e-9)
        XCTAssertEqual(GlucoseStatistics.percentile(v, 0.95), 48, accuracy: 1e-9)
        XCTAssertEqual(GlucoseStatistics.percentile([42], 0.5), 42, accuracy: 1e-9)
        XCTAssertTrue(GlucoseStatistics.percentile([], 0.5).isNaN)
    }

    // MARK: - Average & GMI

    func testAverageAndGMI() {
        let start = midnight
        let samples = (0..<12).map { sample(154, at: start.addingTimeInterval(.minutes(Double($0) * 5))) }
        let stats = GlucoseStatistics(samples: samples, start: start, end: start.addingTimeInterval(.hours(1)))
        XCTAssertEqual(stats.averageGlucose!, 154, accuracy: 1e-6)
        // GMI = 3.31 + 0.02392 * 154
        XCTAssertEqual(stats.gmi!, 3.31 + 0.02392 * 154, accuracy: 1e-6)
        XCTAssertEqual(stats.gmi!, 6.99, accuracy: 0.01)
    }

    // MARK: - Coefficient of variation

    func testCoefficientOfVariation() {
        let start = midnight
        // mean 100, sample SD = sqrt(((-10)^2+10^2)/1) = sqrt(200) ≈ 14.142 -> CV ≈ 14.142%
        let samples = [sample(90, at: start), sample(110, at: start.addingTimeInterval(.minutes(5)))]
        let stats = GlucoseStatistics(samples: samples, start: start, end: start.addingTimeInterval(.minutes(10)))
        XCTAssertEqual(stats.coefficientOfVariation!, 200.0.squareRoot(), accuracy: 1e-6)
    }

    func testCoefficientOfVariationNilForSingleSample() {
        let start = midnight
        let stats = GlucoseStatistics(samples: [sample(100, at: start)], start: start, end: start.addingTimeInterval(.hours(1)))
        XCTAssertNil(stats.coefficientOfVariation)
    }

    // MARK: - Time in range (time-weighted, gap-capped)

    func testTimeInRangeEvenSplit() {
        let start = midnight
        // Two target (100) then two low (60), evenly 5-min spaced, window snug to data.
        let samples = [
            sample(100, at: start),
            sample(100, at: start.addingTimeInterval(.minutes(5))),
            sample(60,  at: start.addingTimeInterval(.minutes(10))),
            sample(60,  at: start.addingTimeInterval(.minutes(15))),
        ]
        let stats = GlucoseStatistics(samples: samples, start: start, end: start.addingTimeInterval(.minutes(20)))
        XCTAssertEqual(stats.timeInRange[.target]!, 0.5, accuracy: 1e-6)
        XCTAssertEqual(stats.timeInRange[.low]!, 0.5, accuracy: 1e-6)
        XCTAssertNil(stats.timeInRange[.veryHigh])
    }

    func testTimeInRangeBandClassification() {
        let start = midnight
        let samples = [
            sample(40,  at: start),                                   // veryLow (<54)
            sample(60,  at: start.addingTimeInterval(.minutes(5))),   // low (54–69)
            sample(120, at: start.addingTimeInterval(.minutes(10))),  // target (70–180)
            sample(220, at: start.addingTimeInterval(.minutes(15))),  // high (181–250)
            sample(300, at: start.addingTimeInterval(.minutes(20))),  // veryHigh (>250)
        ]
        let stats = GlucoseStatistics(samples: samples, start: start, end: start.addingTimeInterval(.minutes(25)))
        for band in GlucoseBand.allCases {
            XCTAssertEqual(stats.timeInRange[band]!, 0.2, accuracy: 1e-6, "band \(band)")
        }
    }

    /// A reading converted from mmol/L sits between whole mg/dL values, so the band edges
    /// have to leave no gap: 10.0 mmol/L is in range and 13.9 mmol/L is high, as the
    /// consensus defines them in mmol/L.
    func testBandEdgesBetweenWholeMilligrams() {
        XCTAssertEqual(GlucoseBand.classify(mgdl: 53.9), .veryLow)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 54), .low)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 69.9), .low)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 70), .target)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 180.4), .target)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 10.0 * 18.0156), .target)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 181), .high)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 13.9 * 18.0156), .high)
        XCTAssertEqual(GlucoseBand.classify(mgdl: 251), .veryHigh)
    }

    func testStandardDeviation() {
        let start = midnight
        let samples = [sample(90, at: start), sample(110, at: start.addingTimeInterval(.minutes(5)))]
        let stats = GlucoseStatistics(samples: samples, start: start, end: start.addingTimeInterval(.minutes(10)))
        XCTAssertEqual(stats.standardDeviation!, 200.0.squareRoot(), accuracy: 1e-6)
        XCTAssertNil(GlucoseStatistics(samples: [samples[0]], start: start, end: start.addingTimeInterval(.hours(1))).standardDeviation)
    }

    // MARK: - Percent active

    func testPercentActive() {
        let start = midnight
        // 6 readings over a 60-min window at 5-min assumed cadence -> 30 min covered -> 50%.
        let samples = (0..<6).map { sample(120, at: start.addingTimeInterval(.minutes(Double($0) * 10))) }
        let stats = GlucoseStatistics(samples: samples, start: start, end: start.addingTimeInterval(.hours(1)))
        XCTAssertEqual(stats.percentActive, 0.5, accuracy: 1e-6)
    }

    /// A sensor that reports every minute covers only the minutes it reports, not five
    /// minutes a reading.
    func testPercentActiveWithOneMinuteReadings() {
        let start = midnight
        let end = start.addingTimeInterval(.hours(1))
        // Readings every minute for the first 20 minutes, then nothing.
        let readings = (0..<20).map { (date: start.addingTimeInterval(.minutes(Double($0))), mgdl: 120.0) }
        let stats = GlucoseStatistics(readings: readings, start: start, end: end)
        XCTAssertEqual(stats.percentActive, 24.0 / 60, accuracy: 1e-6)  // 19 one-minute gaps, then one 5-minute slot
        XCTAssertEqual(stats.timeInRange[.target]!, 1, accuracy: 1e-6)
    }

    /// Readings thinned to one every 2½ minutes and readings every minute give the same coverage.
    func testPercentActiveDoesNotDependOnCadence() {
        let start = midnight
        let end = start.addingTimeInterval(.hours(1))
        let everyMinute = (0..<60).map { (date: start.addingTimeInterval(.minutes(Double($0))), mgdl: 120.0) }
        let thinned = stride(from: 0.0, to: 60, by: 2.5).map { (date: start.addingTimeInterval(.minutes($0)), mgdl: 120.0) }
        XCTAssertEqual(GlucoseStatistics(readings: everyMinute, start: start, end: end).percentActive, 1, accuracy: 1e-6)
        XCTAssertEqual(GlucoseStatistics(readings: thinned, start: start, end: end).percentActive, 1, accuracy: 1e-6)
    }

    // MARK: - AGP profile

    func testAGPProfileBucketing() {
        let start = midnight
        let end = start.addingTimeInterval(.hours(24))
        // Six readings within the 08:00–08:30 bucket (one slot), values spread.
        let eight = start.addingTimeInterval(.hours(8))
        let vals: [Double] = [80, 100, 120, 140, 160, 180]
        let samples = vals.enumerated().map { sample($0.element, at: eight.addingTimeInterval(.minutes(Double($0.offset)))) }
        let stats = GlucoseStatistics(samples: samples, start: start, end: end, calendar: cal)

        XCTAssertEqual(stats.agpProfile.count, 1)
        let band = stats.agpProfile[0]
        // 08:00–08:30 bucket midpoint = 8h15m = 29700s.
        XCTAssertEqual(band.timeOfDay, 29700, accuracy: 1e-6)
        // p50 of [80,100,120,140,160,180] = 130.
        XCTAssertEqual(band.p50, 130, accuracy: 1e-6)
        XCTAssertLessThan(band.p05, band.p50)
        XCTAssertGreaterThan(band.p95, band.p50)
    }

    func testAGPSkipsSparseBuckets() {
        let start = midnight
        let end = start.addingTimeInterval(.hours(24))
        // Only two readings in a bucket (below the min-3 threshold) -> skipped.
        let samples = [sample(120, at: start.addingTimeInterval(.hours(8))),
                       sample(130, at: start.addingTimeInterval(.hours(8).advanced(by: .minutes(1))))]
        let stats = GlucoseStatistics(samples: samples, start: start, end: end, calendar: cal)
        XCTAssertTrue(stats.agpProfile.isEmpty)
    }

    // MARK: - Empty window

    func testEmptyWindow() {
        let start = midnight
        let stats = GlucoseStatistics(samples: [], start: start, end: start.addingTimeInterval(.hours(24)))
        XCTAssertEqual(stats.sampleCount, 0)
        XCTAssertNil(stats.averageGlucose)
        XCTAssertNil(stats.gmi)
        XCTAssertNil(stats.coefficientOfVariation)
        XCTAssertTrue(stats.timeInRange.isEmpty)
        XCTAssertEqual(stats.percentActive, 0)
        XCTAssertTrue(stats.agpProfile.isEmpty)
    }

    func testSamplesOutsideWindowExcluded() {
        let start = midnight
        let end = start.addingTimeInterval(.hours(1))
        let samples = [
            sample(100, at: start.addingTimeInterval(.minutes(-30))), // before window
            sample(120, at: start.addingTimeInterval(.minutes(30))),  // inside
            sample(140, at: end.addingTimeInterval(.minutes(30))),    // after window
        ]
        let stats = GlucoseStatistics(samples: samples, start: start, end: end)
        XCTAssertEqual(stats.sampleCount, 1)
        XCTAssertEqual(stats.averageGlucose!, 120, accuracy: 1e-6)
    }

    // MARK: - Band labels

    /// The consensus band edges are defined in mg/dL, but the labels have to
    /// read in whatever unit the user has chosen — these are the mmol/L edges
    /// the AGP report prints.
    func testBandRangesRenderInTheDisplayUnit() {
        let mgdl = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        XCTAssertEqual(GlucoseBand.veryLow.rangeDescription(mgdl), "<54")
        XCTAssertEqual(GlucoseBand.low.rangeDescription(mgdl), "54\u{2013}69")
        XCTAssertEqual(GlucoseBand.target.rangeDescription(mgdl), "70\u{2013}180")
        XCTAssertEqual(GlucoseBand.high.rangeDescription(mgdl), "181\u{2013}250")
        XCTAssertEqual(GlucoseBand.veryHigh.rangeDescription(mgdl), ">250")

        let mmol = DisplayGlucosePreference(displayGlucoseUnit: .millimolesPerLiter)
        XCTAssertEqual(GlucoseBand.veryLow.rangeDescription(mmol), "<3.0")
        XCTAssertEqual(GlucoseBand.low.rangeDescription(mmol), "3.0\u{2013}3.8")
        XCTAssertEqual(GlucoseBand.target.rangeDescription(mmol), "3.9\u{2013}10.0")
        XCTAssertEqual(GlucoseBand.high.rangeDescription(mmol), "10.1\u{2013}13.9")
        XCTAssertEqual(GlucoseBand.veryHigh.rangeDescription(mmol), ">13.9")
    }
}
