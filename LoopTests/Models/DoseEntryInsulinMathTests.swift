//
//  DoseEntryInsulinMathTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopAlgorithm
@testable import LoopKit
@testable import Loop

fileprivate struct NewReservoirValue: ReservoirValue {
    let startDate: Date
    let unitVolume: Double
}

fileprivate extension DoseUnit {
    var unit: LoopUnit {
        switch self {
        case .units:
            return .internationalUnit
        case .unitsPerHour:
            return .internationalUnitsPerHour
        }
    }
}

fileprivate extension DoseEntry {

    func basalRelativeDose(with insulinModel: LoopKit.InsulinModel) -> BasalRelativeDose {
        var basalRelativeDoseType: BasalRelativeDoseType
        switch type {
        case .bolus:
            basalRelativeDoseType = .bolus
        case .basal:
            basalRelativeDoseType = .basal(scheduledRate: value)
        default:
            if let scheduledRate = scheduledBasalRate?.doubleValue(for: .internationalUnitsPerHour) {
                basalRelativeDoseType = .basal(scheduledRate: scheduledRate)
            } else {
                basalRelativeDoseType = .basal(scheduledRate: 0)  // Seems odd, but this is existing behavior
            }
        }

        return BasalRelativeDose(
            type: basalRelativeDoseType,
            startDate: startDate,
            endDate: endDate,
            volume: deliveredUnits ?? programmedUnits,
            insulinModel: AlgorithmInsulinModel(insulinModel)
        )
    }
}

fileprivate extension BasalRelativeDose {
    var netBasalUnitsPerHour: Double {
        if duration > 0 {
            return netBasalUnits / duration.hours
        } else {
            return 0
        }
    }

    public var unitsPerHour: Double {
        return volume / duration.hours
    }
}

class DoseEntryInsulinMathTests: XCTestCase {

    private var fixtureDateformatter: DateFormatter!

    private let fixtureTimeZone = TimeZone(secondsFromGMT: 0)!

    let exponentialModel = ExponentialInsulinModel(actionDuration: TimeInterval(minutes: 360), peakActivityTime: TimeInterval(minutes: 75))

    let standardInsulinModel = ExponentialInsulinModelPreset.rapidActingAdult.model

    let walshModel = WalshInsulinModel(actionDuration: TimeInterval(hours: 4))

    private func fixtureDate(_ input: String) -> Date {
        return fixtureDateformatter.date(from: input)!
    }

    override func setUp() {
        fixtureDateformatter = DateFormatter.descriptionFormatter
        fixtureDateformatter.timeZone = fixtureTimeZone
    }

    private func loadFixture<T>(_ resourceName: String) -> T {
        let path = Bundle(for: type(of: self)).path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }

    private func printInsulinValues(_ insulinValues: [LoopAlgorithm.InsulinValue]) {
        print("\n\n")
        print(String(data: try! JSONSerialization.data(
            withJSONObject: insulinValues.map({ (value) -> [String: Any] in
                return [
                    "date": ISO8601DateFormatter.localTimeDate(timeZone: fixtureTimeZone).string(from: value.startDate),
                    "value": value.value,
                    "unit": "U"
                ]
            }),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!)
        print("\n\n")
    }

    private func loadReservoirFixture(_ resourceName: String) -> [NewReservoirValue] {

        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = ISO8601DateFormatter.localTimeDate(timeZone: fixtureTimeZone)

        return fixture.map {
            return NewReservoirValue(startDate: dateFormatter.date(from: $0["date"] as! String)!, unitVolume: $0["amount"] as! Double)
        }
    }

    func loadDoseFixture(_ resourceName: String, insulinType: InsulinType? = .novolog) -> [DoseEntry] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = ISO8601DateFormatter.localTimeDate(timeZone: fixtureTimeZone)

        return fixture.compactMap {
            guard let unit = DoseUnit(rawValue: $0["unit"] as! String),
                  let pumpType = PumpEventType(rawValue: $0["type"] as! String),
                  let type = DoseType(pumpEventType: pumpType)
            else {
                return nil
            }
            
            let decisionId = $0["decisionId"] as? String

            var dose = DoseEntry(
                type: type,
                startDate: dateFormatter.date(from: $0["start_at"] as! String)!,
                endDate: dateFormatter.date(from: $0["end_at"] as! String)!,
                value: $0["amount"] as! Double,
                unit: unit,
                decisionId: UUID(uuidString: decisionId ?? ""),
                deliveredUnits: $0["delivered"] as? Double,
                description: $0["description"] as? String,
                syncIdentifier: $0["raw"] as? String,
                insulinType: insulinType,
                automatic: $0["automatic"] as? Bool,
                manuallyEntered: $0["manuallyEntered"] as? Bool ?? false,
                isMutable: $0["isMutable"] as? Bool ?? false
            )

            if let scheduled = $0["scheduled"] as? Double {
                dose.scheduledBasalRate = LoopQuantity(unit: unit.unit, doubleValue: scheduled)
            }

            return dose
        }
    }

    func loadInsulinValueFixture(_ resourceName: String) -> [InsulinValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = ISO8601DateFormatter.localTimeDate(timeZone: fixtureTimeZone)

        return fixture.map {
            return InsulinValue(startDate: dateFormatter.date(from: $0["date"] as! String)!, value: $0["value"] as! Double)
        }
    }

    func loadBasalRateScheduleFixture(_ resourceName: String) -> BasalRateSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)

        let items = fixture.map {
            return RepeatingScheduleValue(startTime: TimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }

        return BasalRateSchedule(dailyItems: items, timeZone: fixtureTimeZone)!
    }

    func testIOBFromSuspend() {
        let input = loadDoseFixture("suspend_dose")
        let reconciledOutput = loadDoseFixture("suspend_dose_reconciled")
        let normalizedOutput = loadDoseFixture("suspend_dose_reconciled_normalized")
        let iobOutput = loadInsulinValueFixture("suspend_dose_reconciled_normalized_iob")
        let basals = loadBasalRateScheduleFixture("basal")

        let reconciled = input.reconciled()

        XCTAssertEqual(reconciledOutput.count, reconciled.count)

        for (expected, calculated) in zip(reconciledOutput, reconciled) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqual(expected.value, calculated.value)
            XCTAssertEqual(expected.unit, calculated.unit)
        }

        let basalTimeline = basals.between(start: input.first!.startDate, end: input.first!.startDate).algorithmSchedule()

        let reconciledWithModel = reconciled.map { $0.toMockInsulinDose(with: walshModel) }

        let normalized = reconciledWithModel.annotated(with: basalTimeline)

        XCTAssertEqual(normalizedOutput.count, normalized.count)

        for (expected, calculated) in zip(normalizedOutput, normalized) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqual(expected.value, calculated.netBasalUnitsPerHour, accuracy: Double(Float.ulpOfOne))
        }

        let iob = normalized.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)

        XCTAssertEqual(iobOutput.count, iob.count)

        for (expected, calculated) in zip(iobOutput, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: Double(Float.ulpOfOne))
        }
    }

    func testIOBFromDoses() {
        let input = loadDoseFixture("normalized_doses", insulinType: .novolog)
        let output = loadInsulinValueFixture("iob_from_doses_output")

        let basalRelativeInput = input.map { $0.basalRelativeDose(with: walshModel) }

        measure {
            _ = basalRelativeInput.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)
        }

        let iob = basalRelativeInput.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)

        XCTAssertEqual(output.count, iob.count)

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.5)
        }
    }

    func testIOBFromNoDoses() {
        let input: [DoseEntry] = []

        let basalRelativeInput = input.map { $0.basalRelativeDose(with: standardInsulinModel) }

        let iob = basalRelativeInput.insulinOnBoardTimeline(longestEffectDuration: standardInsulinModel.effectDuration)

        XCTAssertEqual(0, iob.count)
    }

    func testIOBFromDosesExponential() {
        let input = loadDoseFixture("normalized_doses", insulinType: .novolog)
        let output = loadInsulinValueFixture("iob_from_doses_exponential_output")

        let basalRelativeInput = input.map { $0.basalRelativeDose(with: exponentialModel) }

        measure {
            _ = basalRelativeInput.insulinOnBoardTimeline(longestEffectDuration: exponentialModel.effectDuration)
        }
        
        let iob = basalRelativeInput.insulinOnBoardTimeline()

        XCTAssertEqual(output.count, iob.count)
        
        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.5)
        }
    }

    func testIOBFromDosesWithDifferentInsulinCurves() {
        let formatter = DateFormatter.descriptionFormatter
        let f = { (input) in
            return formatter.date(from: input)!
        }
        let output = loadInsulinValueFixture("iob_from_multiple_curves_output")

        let doses = [
            DoseEntry(type: .basal, startDate: f("2018-05-15 14:42:36 +0000"), endDate: f("2018-05-16 14:42:36 +0000"), value: 0.84999999999999998, unit: .unitsPerHour, decisionId: nil, syncIdentifier: "7b02646a070f120e2200", scheduledBasalRate: nil),
            DoseEntry(type: .bolus, startDate: f("2018-05-15 14:44:46 +0000"), endDate: f("2018-05-15 14:44:46 +0000"), value: 0.9, unit: .units, decisionId: nil, syncIdentifier: "01004a004a006d006e22354312", scheduledBasalRate: nil),
            DoseEntry(type: .tempBasal, startDate: f("2018-05-15 14:42:36 +0000"), endDate: f("2018-05-15 14:42:36 +0000"), value: 0.0, unit: .unitsPerHour, decisionId: nil, syncIdentifier: "1600646a074f12", scheduledBasalRate: nil),
            DoseEntry(type: .tempBasal, startDate: f("2018-05-15 14:32:51 +0000"), endDate: f("2018-05-15 15:02:51 +0000"), value: 1.8999999999999999, unit: .unitsPerHour, decisionId: nil, syncIdentifier: "16017360074f12", scheduledBasalRate: nil),
            DoseEntry(type: .bolus, startDate: f("2018-05-15 14:52:51 +0000"), endDate: f("2018-05-15 15:52:51 +0000"), value: 0.9, unit: .units, decisionId: nil, syncIdentifier: "01004a004a006d006e22354312", scheduledBasalRate: nil),
        ]

        let basalRelativeInput = doses.map { $0.basalRelativeDose(with: exponentialModel) }

        let iobWithoutModel = basalRelativeInput.insulinOnBoardTimeline()

        let dosesWithModel = [
            DoseEntry(type: .basal, startDate: f("2018-05-15 14:42:36 +0000"), endDate: f("2018-05-16 14:42:36 +0000"), value: 0.84999999999999998, unit: .unitsPerHour, decisionId: nil, syncIdentifier: "7b02646a070f120e2200", scheduledBasalRate: nil),
            DoseEntry(type: .bolus, startDate: f("2018-05-15 14:44:46 +0000"), endDate: f("2018-05-15 14:44:46 +0000"), value: 0.9, unit: .units, decisionId: nil, syncIdentifier: "01004a004a006d006e22354312", scheduledBasalRate: nil, insulinType: .fiasp),
            DoseEntry(type: .tempBasal, startDate: f("2018-05-15 14:42:36 +0000"), endDate: f("2018-05-15 14:42:36 +0000"), value: 0.0, unit: .unitsPerHour, decisionId: nil, syncIdentifier: "1600646a074f12", scheduledBasalRate: nil),
            DoseEntry(type: .tempBasal, startDate: f("2018-05-15 14:32:51 +0000"), endDate: f("2018-05-15 15:02:51 +0000"), value: 1.8999999999999999, unit: .unitsPerHour, decisionId: nil, syncIdentifier: "16017360074f12", scheduledBasalRate: nil),
            DoseEntry(type: .bolus, startDate: f("2018-05-15 14:52:51 +0000"), endDate: f("2018-05-15 15:52:51 +0000"), value: 0.9, unit: .units, decisionId: nil, syncIdentifier: "01004a004a006d006e22354312", scheduledBasalRate: nil, insulinType: .novolog),
        ]

        let dosesWithModelRelative = dosesWithModel.map { entry in
            let insulinModel: InsulinModel
            switch entry.insulinType {
            case .fiasp:
                insulinModel = ExponentialInsulinModelPreset.fiasp
            default:
                insulinModel = ExponentialInsulinModelPreset.rapidActingChild
            }
            return entry.basalRelativeDose(with: insulinModel) }

        let iobWithModel = dosesWithModelRelative.insulinOnBoardTimeline()

        XCTAssertEqual(iobWithoutModel.count, iobWithModel.count)

        for (expected, calculated) in zip(output, iobWithModel) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.00001)
        }

    }

    func testIOBFromReservoirDoses() {
        let input = loadDoseFixture("normalized_reservoir_history_output")
        let output = loadInsulinValueFixture("iob_from_reservoir_output")

        let basalRelativeInput = input.map { $0.basalRelativeDose(with: walshModel) }

        measure {
            _ = basalRelativeInput.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)
        }

        let iob = basalRelativeInput.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)

        XCTAssertEqual(output.count, iob.count)

        printInsulinValues(iob)

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.01)
        }
    }

    func testNormalizeReservoirDoses() {
        let input = loadDoseFixture("reservoir_history_with_rewind_and_prime_output")
        let output = loadDoseFixture("normalized_reservoir_history_output")
        let basals = loadBasalRateScheduleFixture("basal")

        let basalTimeline = basals.between(start: input.last!.startDate, end: input.first!.endDate).algorithmSchedule()

        let inputWithModel = input.map { $0.toMockInsulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult.model) }


        measure {
            _ = inputWithModel.annotated(with: basalTimeline)
        }

        let doses = inputWithModel.annotated(with: basalTimeline)

        XCTAssertEqual(output.count, doses.count)

        // Total delivery on split doses should add up to delivery from original doses
        XCTAssertEqual(
            input.map {$0.unitsInDeliverableIncrements}.reduce(0,+),
            doses.map {$0.volume}.reduce(0,+),
            accuracy: Double(Float.ulpOfOne))

        for (expected, calculated) in zip(output, doses) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqual(expected.value, calculated.unitsPerHour, accuracy: Double(Float.ulpOfOne))
            switch calculated.type {
            case .basal(let scheduledRate):
                XCTAssertEqual(expected.scheduledBasalRate?.doubleValue(for: .internationalUnitsPerHour), scheduledRate)
            case .bolus:
                XCTFail("Unexpected bolus in dose history")
            }
        }
    }

    func testNormalizeEdgeCaseDoses() {
        let input = loadDoseFixture("normalize_edge_case_doses_input")
        let output = loadDoseFixture("normalize_edge_case_doses_output")
        let basals = loadBasalRateScheduleFixture("basal")

        let basalTimeline = basals.between(start: input.first!.startDate, end: input.last!.endDate).algorithmSchedule()

        let inputWithModel = input.map { $0.toMockInsulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult.model) }


        measure {
            _ = inputWithModel.annotated(with: basalTimeline)
        }

        let doses = inputWithModel.annotated(with: basalTimeline)

        XCTAssertEqual(output.count, doses.count)

        for (expected, calculated) in zip(output, doses) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqual(expected.value, expected.unit == .units ? calculated.netBasalUnits : calculated.netBasalUnitsPerHour, accuracy: 0.01)
        }
    }

    func testNormalizeEdgeCaseDosesMutable() {
        let input = loadDoseFixture("normalize_edge_case_doses_mutable_input")
        let output = loadDoseFixture("normalize_edge_case_doses_mutable_output")
        let basals = loadBasalRateScheduleFixture("basal")

        let basalTimeline = basals.between(start: input.first!.startDate, end: input.last!.endDate).algorithmSchedule()

        let inputWithModel = input.map { $0.toMockInsulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult.model) }

        measure {
            _ = inputWithModel.annotated(with: basalTimeline)
        }

        let doses = inputWithModel.annotated(with: basalTimeline)

        XCTAssertEqual(output.count, doses.count)

        for (expected, calculated) in zip(output, doses) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqual(expected.value, expected.unit == .units ? calculated.netBasalUnits : calculated.netBasalUnitsPerHour, accuracy: 0.01)
        }
    }

    func testDoseEntryAnnotateShouldSplitDosesProportionally() {
        let startDate = self.fixtureDate("2018-07-16 11:59:00 +0000")
        let endDate = startDate.addingTimeInterval(TimeInterval(minutes: 5))

        let tempBasalRate = 1.0

        let dose = DoseEntry(
            type: .tempBasal,
            startDate: startDate,
            endDate: endDate,
            value: tempBasalRate,
            unit: .unitsPerHour,
            decisionId: nil,
            deliveredUnits: 0.1
        )

        let delivery = dose.unitsInDeliverableIncrements

        let basals = loadBasalRateScheduleFixture("basal").between(start: startDate, end: endDate).algorithmSchedule()

        let doseWithModel = dose.toMockInsulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult.model)

        let splitDoses = [doseWithModel].annotated(with: basals)

        XCTAssertEqual(2, splitDoses.count)

        // A 5 minute dose starting one minute before midnight, split at midnight, means split should be 1/5, 4/5
        XCTAssertEqual(delivery * 1.0/5.0, splitDoses[0].volume, accuracy: .ulpOfOne)
        XCTAssertEqual(delivery * 4.0/5.0, splitDoses[1].volume, accuracy: .ulpOfOne)
    }

    func testDoseEntryWithoutDeliveredUnitsShouldSplitDosesProportionally() {
        let startDate = self.fixtureDate("2018-07-16 11:59:00 +0000")
        let endDate = startDate.addingTimeInterval(TimeInterval(minutes: 5))

        let tempBasalRate = 1.0

        let dose = DoseEntry(
            type: .tempBasal,
            startDate: startDate,
            endDate: endDate,
            value: tempBasalRate,
            unit: .unitsPerHour,
            decisionId: nil,
            deliveredUnits: 0.05
        )

        let delivery = dose.unitsInDeliverableIncrements

        let basals = loadBasalRateScheduleFixture("basal").between(start: startDate, end: endDate).algorithmSchedule()

        let doseWithModel = dose.toMockInsulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult.model)

        let splitDoses = [doseWithModel].annotated(with: basals)

        XCTAssertEqual(2, splitDoses.count)

        // A 5 minute dose starting one minute before midnight, split at midnight, means split should be 1/5, 4/5
        XCTAssertEqual(delivery * 1.0/5.0, splitDoses[0].volume, accuracy: .ulpOfOne)
        XCTAssertEqual(delivery * 4.0/5.0, splitDoses[1].volume, accuracy: .ulpOfOne)
    }
}

fileprivate struct MockInsulinDose: InsulinDose {
    var deliveryType: InsulinDeliveryType

    var startDate: Date

    var endDate: Date

    var volume: Double

    var insulinModel: LoopAlgorithm.InsulinModel
}

fileprivate extension DoseEntry {
    func toMockInsulinDose(with insulinModel: LoopKit.InsulinModel) -> MockInsulinDose {
        return MockInsulinDose(
            deliveryType: type == .bolus ? .bolus : .basal,
            startDate: startDate,
            endDate: endDate,
            volume: deliveredUnits ?? programmedUnits,
            insulinModel: AlgorithmInsulinModel(insulinModel)
        )
    }
}
