//
//  LoopInsights_DataAggregatorTests.swift
//  LoopTests
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import HealthKit
@testable import Loop

// MARK: - Mock Data Provider

final class MockLoopInsightsDataProvider: LoopInsightsDataProviderProtocol {

    var mockGlucoseSamples: [StoredGlucoseSample] = []
    var mockCarbEntries: [StoredCarbEntry] = []
    var mockDoseEntries: [DoseEntry] = []
    var mockSettings: StoredSettings = StoredSettings()

    func getGlucoseSamples(start: Date, end: Date) async throws -> [StoredGlucoseSample] {
        return mockGlucoseSamples.filter { $0.startDate >= start && $0.startDate <= end }
    }

    func getCarbEntries(start: Date, end: Date) async throws -> [StoredCarbEntry] {
        return mockCarbEntries.filter { $0.startDate >= start && $0.startDate <= end }
    }

    func getNormalizedDoseEntries(start: Date, end: Date) async throws -> [DoseEntry] {
        return mockDoseEntries.filter { $0.startDate >= start && $0.startDate <= end }
    }

    func getLatestStoredSettings() -> StoredSettings {
        return mockSettings
    }
}

// MARK: - Tests

final class LoopInsights_DataAggregatorTests: XCTestCase {

    private var mockProvider: MockLoopInsightsDataProvider!
    private var aggregator: LoopInsights_DataAggregator!

    override func setUp() {
        super.setUp()
        mockProvider = MockLoopInsightsDataProvider()
        aggregator = LoopInsights_DataAggregator(dataProvider: mockProvider)
    }

    // MARK: - Glucose Stats

    func testGlucoseStatsCalculation() async throws {
        // Create mock glucose samples spanning 7 days
        let now = Date()
        var samples: [StoredGlucoseSample] = []
        let calendar = Calendar.current

        // Create samples every 5 minutes for 7 days
        // Mix of in-range, low, and high values
        for dayOffset in 0..<7 {
            for hourOffset in 0..<24 {
                for minuteOffset in stride(from: 0, to: 60, by: 5) {
                    let date = calendar.date(byAdding: .day, value: -dayOffset, to: now)!
                    let dateWithHour = calendar.date(byAdding: .hour, value: -hourOffset, to: date)!
                    let dateWithMinute = calendar.date(byAdding: .minute, value: -minuteOffset, to: dateWithHour)!

                    // Simulate realistic glucose: mostly in range with some highs after meals
                    var glucose: Double
                    if hourOffset >= 7 && hourOffset <= 9 {
                        glucose = Double.random(in: 140...200) // Post-breakfast highs
                    } else if hourOffset >= 12 && hourOffset <= 14 {
                        glucose = Double.random(in: 130...180) // Post-lunch
                    } else {
                        glucose = Double.random(in: 80...140) // Normal range
                    }

                    let sample = StoredGlucoseSample(
                        uuid: UUID(),
                        provenanceIdentifier: "test",
                        syncIdentifier: UUID().uuidString,
                        syncVersion: 1,
                        startDate: dateWithMinute,
                        quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: glucose),
                        condition: nil,
                        trend: nil,
                        trendRate: nil,
                        isDisplayOnly: false,
                        wasUserEntered: false,
                        device: nil,
                        healthKitEligibleDate: nil
                    )
                    samples.append(sample)
                }
            }
        }

        mockProvider.mockGlucoseSamples = samples

        let stats = try await aggregator.aggregateData(period: .sevenDays)

        // Verify glucose stats are reasonable
        XCTAssertGreaterThan(stats.glucoseStats.averageGlucose, 0)
        XCTAssertGreaterThan(stats.glucoseStats.standardDeviation, 0)
        XCTAssertGreaterThan(stats.glucoseStats.timeInRange, 0)
        XCTAssertEqual(stats.glucoseStats.timeInRange + stats.glucoseStats.timeBelowRange + stats.glucoseStats.timeAboveRange, 100, accuracy: 0.1)
        XCTAssertGreaterThan(stats.glucoseStats.gmi, 0)
        XCTAssertGreaterThan(stats.glucoseStats.sampleCount, 0)
    }

    func testInsufficientDataThrows() async {
        // No glucose samples
        mockProvider.mockGlucoseSamples = []

        do {
            _ = try await aggregator.aggregateData(period: .sevenDays)
            XCTFail("Should have thrown insufficientData error")
        } catch let error as LoopInsightsError {
            if case .insufficientData = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - GMI Calculation

    func testGMICalculation() async throws {
        // Create samples with known average glucose
        let now = Date()
        let targetGlucose = 154.0 // Should give GMI ≈ 7.0

        var samples: [StoredGlucoseSample] = []
        for i in 0..<100 {
            let date = now.addingTimeInterval(TimeInterval(-i * 300)) // 5 min apart
            let sample = StoredGlucoseSample(
                uuid: UUID(),
                provenanceIdentifier: "test",
                syncIdentifier: UUID().uuidString,
                syncVersion: 1,
                startDate: date,
                quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: targetGlucose),
                condition: nil,
                trend: nil,
                trendRate: nil,
                isDisplayOnly: false,
                wasUserEntered: false,
                device: nil,
                healthKitEligibleDate: nil
            )
            samples.append(sample)
        }

        mockProvider.mockGlucoseSamples = samples

        let stats = try await aggregator.aggregateData(period: .sevenDays)

        // GMI = 3.31 + 0.02392 × 154 = 3.31 + 3.68 ≈ 6.99
        XCTAssertEqual(stats.glucoseStats.gmi, 6.99, accuracy: 0.1)
    }
}
