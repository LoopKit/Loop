//
//  LoopInsights_ModelsTests.swift
//  LoopTests
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop

final class LoopInsights_ModelsTests: XCTestCase {

    // MARK: - LoopInsightsSettingType

    func testSettingTypeDisplayNames() {
        XCTAssertEqual(LoopInsightsSettingType.carbRatio.abbreviation, "CR")
        XCTAssertEqual(LoopInsightsSettingType.insulinSensitivity.abbreviation, "ISF")
        XCTAssertEqual(LoopInsightsSettingType.basalRate.abbreviation, "BR")
    }

    func testSettingTypeCodable() throws {
        let original = LoopInsightsSettingType.carbRatio
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LoopInsightsSettingType.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testSettingTypeAllCases() {
        XCTAssertEqual(LoopInsightsSettingType.allCases.count, 3)
    }

    // MARK: - LoopInsightsAnalysisPeriod

    func testAnalysisPeriodTimeIntervals() {
        XCTAssertEqual(LoopInsightsAnalysisPeriod.sevenDays.timeInterval, 7 * 24 * 60 * 60)
        XCTAssertEqual(LoopInsightsAnalysisPeriod.fourteenDays.timeInterval, 14 * 24 * 60 * 60)
        XCTAssertEqual(LoopInsightsAnalysisPeriod.thirtyDays.timeInterval, 30 * 24 * 60 * 60)
    }

    func testAnalysisPeriodCodable() throws {
        let original = LoopInsightsAnalysisPeriod.fourteenDays
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LoopInsightsAnalysisPeriod.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - LoopInsightsApplyMode

    func testApplyModePublicModes() {
        let publicModes = LoopInsightsApplyMode.publicModes
        XCTAssertEqual(publicModes.count, 3)
        XCTAssertFalse(publicModes.contains(.autoApply))
    }

    func testApplyModeCodable() throws {
        let original = LoopInsightsApplyMode.oneTap
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LoopInsightsApplyMode.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - LoopInsightsConfidence

    func testConfidenceComparable() {
        XCTAssertTrue(LoopInsightsConfidence.low < .medium)
        XCTAssertTrue(LoopInsightsConfidence.medium < .high)
        XCTAssertFalse(LoopInsightsConfidence.high < .low)
    }

    func testConfidenceCodable() throws {
        let original = LoopInsightsConfidence.high
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LoopInsightsConfidence.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - LoopInsightsTimeBlock

    func testTimeBlockChangePercent() {
        let block = LoopInsightsTimeBlock(
            startTime: 0,
            endTime: 21600,
            currentValue: 10.0,
            proposedValue: 12.0
        )
        XCTAssertEqual(block.changePercent, 20.0, accuracy: 0.01)
    }

    func testTimeBlockChangePercentDecrease() {
        let block = LoopInsightsTimeBlock(
            startTime: 0,
            endTime: 21600,
            currentValue: 50.0,
            proposedValue: 45.0
        )
        XCTAssertEqual(block.changePercent, -10.0, accuracy: 0.01)
    }

    func testTimeBlockChangePercentZeroCurrent() {
        let block = LoopInsightsTimeBlock(
            startTime: 0,
            endTime: 21600,
            currentValue: 0.0,
            proposedValue: 5.0
        )
        XCTAssertEqual(block.changePercent, 0.0)
    }

    func testTimeBlockCodable() throws {
        let original = LoopInsightsTimeBlock(
            startTime: 21600,
            endTime: 43200,
            currentValue: 10.0,
            proposedValue: 11.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LoopInsightsTimeBlock.self, from: data)
        XCTAssertEqual(decoded.startTime, original.startTime)
        XCTAssertEqual(decoded.endTime, original.endTime)
        XCTAssertEqual(decoded.currentValue, original.currentValue)
        XCTAssertEqual(decoded.proposedValue, original.proposedValue)
    }

    // MARK: - LoopInsightsSuggestion

    func testSuggestionSummaryDescriptionSingleBlock() {
        let suggestion = makeSuggestion(blocks: [
            LoopInsightsTimeBlock(startTime: 43200, endTime: 54000, currentValue: 10, proposedValue: 12)
        ])
        XCTAssertTrue(suggestion.summaryDescription.contains("Increase"))
        XCTAssertTrue(suggestion.summaryDescription.contains("CR"))
    }

    func testSuggestionSummaryDescriptionMultiBlock() {
        let suggestion = makeSuggestion(blocks: [
            LoopInsightsTimeBlock(startTime: 0, endTime: 21600, currentValue: 10, proposedValue: 12),
            LoopInsightsTimeBlock(startTime: 21600, endTime: 43200, currentValue: 8, proposedValue: 9)
        ])
        XCTAssertTrue(suggestion.summaryDescription.contains("2"))
    }

    func testSuggestionEquality() {
        let suggestion1 = makeSuggestion(blocks: [])
        let suggestion2 = makeSuggestion(blocks: [])
        XCTAssertNotEqual(suggestion1, suggestion2, "Different UUIDs should not be equal")
        XCTAssertEqual(suggestion1, suggestion1, "Same instance should be equal")
    }

    func testSuggestionCodable() throws {
        let original = makeSuggestion(blocks: [
            LoopInsightsTimeBlock(startTime: 0, endTime: 21600, currentValue: 10, proposedValue: 11)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LoopInsightsSuggestion.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.settingType, original.settingType)
        XCTAssertEqual(decoded.timeBlocks.count, original.timeBlocks.count)
    }

    // MARK: - LoopInsightsTherapySnapshot

    func testTherapySnapshotCodable() throws {
        let snapshot = LoopInsightsTherapySnapshot(
            basalRateItems: [
                .init(startTime: 0, value: 0.8),
                .init(startTime: 21600, value: 1.0)
            ],
            insulinSensitivityItems: [
                .init(startTime: 0, value: 50)
            ],
            carbRatioItems: [
                .init(startTime: 0, value: 10)
            ],
            capturedAt: Date()
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LoopInsightsTherapySnapshot.self, from: data)
        XCTAssertEqual(decoded.basalRateItems.count, 2)
        XCTAssertEqual(decoded.insulinSensitivityItems.count, 1)
        XCTAssertEqual(decoded.carbRatioItems.count, 1)
    }

    // MARK: - LoopInsightsRequestFormat

    func testRequestFormatAutoDetection() {
        XCTAssertEqual(LoopInsightsRequestFormat.detect(from: "https://api.openai.com/v1"), .openAICompatible)
        XCTAssertEqual(LoopInsightsRequestFormat.detect(from: "https://api.anthropic.com/v1"), .anthropicMessages)
        XCTAssertEqual(LoopInsightsRequestFormat.detect(from: "https://generativelanguage.googleapis.com/v1beta"), .googleGenerativeAI)
        // Unknown URL falls back to OpenAI-compatible
        XCTAssertEqual(LoopInsightsRequestFormat.detect(from: "https://my-custom-llm.com/v1"), .openAICompatible)
    }

    func testRequestFormatDefaults() {
        XCTAssertEqual(LoopInsightsRequestFormat.openAICompatible.defaultAPIKeyHeader, "Authorization")
        XCTAssertEqual(LoopInsightsRequestFormat.anthropicMessages.defaultAPIKeyHeader, "x-api-key")
        XCTAssertEqual(LoopInsightsRequestFormat.openAICompatible.defaultAPIKeyPrefix, "Bearer ")
        XCTAssertEqual(LoopInsightsRequestFormat.anthropicMessages.defaultAPIKeyPrefix, "")
    }

    // MARK: - LoopInsightsAIProviderConfiguration

    func testConfigurationCodableExcludesAPIKey() throws {
        var config = LoopInsightsAIProviderConfiguration(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-secret-key"
        )
        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8)!
        // API key must NOT appear in serialized output
        XCTAssertFalse(json.contains("sk-secret-key"))

        let decoded = try JSONDecoder().decode(LoopInsightsAIProviderConfiguration.self, from: data)
        XCTAssertEqual(decoded.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(decoded.model, "gpt-4o")
        XCTAssertEqual(decoded.apiKey, "", "API key should be empty after decoding")
    }

    func testConfigurationDefaultValues() {
        let config = LoopInsightsAIProviderConfiguration()
        XCTAssertEqual(config.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(config.model, "gpt-4o")
        XCTAssertEqual(config.requestFormat, .openAICompatible)
        XCTAssertEqual(config.maxTokens, 4096)
        XCTAssertEqual(config.temperature, 0.3, accuracy: 0.001)
        XCTAssertNil(config.apiVersion)
        XCTAssertNil(config.organizationID)
    }

    // MARK: - LoopInsightsError

    func testErrorDescriptions() {
        let noKey = LoopInsightsError.noAPIKeyConfigured
        XCTAssertNotNil(noKey.errorDescription)
        XCTAssertTrue(noKey.errorDescription!.contains("API key"))

        let parseError = LoopInsightsError.parseError("bad json")
        XCTAssertTrue(parseError.errorDescription!.contains("bad json"))
    }

    // MARK: - Helpers

    private func makeSuggestion(blocks: [LoopInsightsTimeBlock]) -> LoopInsightsSuggestion {
        return LoopInsightsSuggestion(
            id: UUID(),
            settingType: .carbRatio,
            timeBlocks: blocks,
            reasoning: "Test reasoning",
            confidence: .medium,
            analysisPeriod: .fourteenDays,
            createdAt: Date()
        )
    }
}
