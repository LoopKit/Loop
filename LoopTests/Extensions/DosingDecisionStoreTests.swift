//
//  DosingDecisionStoreTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 5/12/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit

@testable import Loop

class StoredDosingDecisionCodableTests: XCTestCase {
    func testCodable() throws {
        let insulinOnBoard = InsulinValue(startDate: dateFormatter.date(from: "2020-05-14T22:38:26Z")!, value: 1.5)
        let carbsOnBoard = CarbValue(startDate: dateFormatter.date(from: "2020-05-14T22:48:41Z")!,
                                     endDate: dateFormatter.date(from: "2020-05-14T23:18:41Z")!,
                                     quantity: HKQuantity(unit: .gram(), doubleValue: 45.5))
        let scheduleOverride = TemporaryScheduleOverride(context: .custom,
                                                         settings: TemporaryScheduleOverrideSettings(unit: .milligramsPerDeciliter,
                                                                                                     targetRange: DoubleRange(minValue: 80.0,
                                                                                                                              maxValue: 90.0),
                                                                                                     insulinNeedsScaleFactor: 0.75),
                                                         startDate: dateFormatter.date(from: "2020-05-14T22:01:23Z")!,
                                                         duration: .finite(.minutes(45)),
                                                         enactTrigger: .local,
                                                         syncIdentifier: UUID(uuidString: "238E41EA-9576-4981-A1A4-51E10228584F")!)
        let glucoseTargetRangeSchedule = GlucoseRangeSchedule(rangeSchedule: DailyQuantitySchedule(unit: .milligramsPerDeciliter,
                                                                                                   dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(7), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(21), value: DoubleRange(minValue: 110.0, maxValue: 120.0))],
                                                                                                   timeZone: TimeZone(identifier: "America/Los_Angeles")!)!,
                                                              override: GlucoseRangeSchedule.Override(value: DoubleRange(minValue: 105.0, maxValue: 115.0),
                                                                                                      start: dateFormatter.date(from: "2020-05-14T21:12:17Z")!,
                                                                                                      end: dateFormatter.date(from: "2020-05-14T23:12:17Z")!))
        let glucoseTargetRangeScheduleApplyingOverrideIfActive = GlucoseRangeSchedule(rangeSchedule: DailyQuantitySchedule(unit: .milligramsPerDeciliter,
                                                                                                                           dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(7), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(21), value: DoubleRange(minValue: 110.0, maxValue: 120.0))],
                                                                                                                           timeZone: TimeZone(identifier: "America/Los_Angeles")!)!,
                                                                                      override: GlucoseRangeSchedule.Override(value: DoubleRange(minValue: 105.0, maxValue: 115.0),
                                                                                                                              start: dateFormatter.date(from: "2020-05-14T21:12:17Z")!,
                                                                                                                              end: dateFormatter.date(from: "2020-05-14T23:12:17Z")!))
        let predictedGlucose = [PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T22:43:15Z")!,
                                                      quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 123.3)),
                                PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T22:48:15Z")!,
                                                      quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 125.5)),
                                PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T22:53:15Z")!,
                                                      quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 127.8))]
        let predictedGlucoseIncludingPendingInsulin = [PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T22:43:15Z")!,
                                                                             quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 113.3)),
                                                       PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T22:48:15Z")!,
                                                                             quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 115.5)),
                                                       PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T22:53:15Z")!,
                                                                             quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 117.8))]
        let lastReservoirValue = StoredDosingDecision.LastReservoirValue(startDate: dateFormatter.date(from: "2020-05-14T22:07:19Z")!,
                                                                         unitVolume: 113.3)
        let recommendedTempBasal = StoredDosingDecision.TempBasalRecommendationWithDate(recommendation: TempBasalRecommendation(unitsPerHour: 0.75,
                                                                                                                                duration: .minutes(30)),
                                                                                        date: dateFormatter.date(from: "2020-05-14T22:38:15Z")!)
        let recommendedBolus = StoredDosingDecision.BolusRecommendationWithDate(recommendation: BolusRecommendation(amount: 1.2,
                                                                                                                    pendingInsulin: 0.75,
                                                                                                                    notice: .predictedGlucoseBelowTarget(minGlucose: PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T23:03:15Z")!,
                                                                                                                                                                                           quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 75.5)))),
                                                                                date: dateFormatter.date(from: "2020-05-14T22:38:16Z")!)
        let pumpManagerStatus = PumpManagerStatus(timeZone: TimeZone(identifier: "America/Los_Angeles")!,
                                                  device: HKDevice(name: "Device Name",
                                                                   manufacturer: "Device Manufacturer",
                                                                   model: "Device Model",
                                                                   hardwareVersion: "Device Hardware Version",
                                                                   firmwareVersion: "Device Firmware Version",
                                                                   softwareVersion: "Device Software Version",
                                                                   localIdentifier: "Device Local Identifier",
                                                                   udiDeviceIdentifier: "Device UDI Device Identifier"),
                                                  pumpBatteryChargeRemaining: 3.5,
                                                  basalDeliveryState: .initiatingTempBasal,
                                                  bolusState: .none)
        let deviceSettings = StoredDosingDecision.DeviceSettings(name: "Device Name",
                                                                 systemName: "Device System Name",
                                                                 systemVersion: "Device System Version",
                                                                 model: "Device Model",
                                                                 modelIdentifier: "Device Model Identifier",
                                                                 batteryLevel: 0.5,
                                                                 batteryState: .charging)
        let errors: [Error] = [CarbStore.CarbStoreError.notConfigured,
                               DoseStore.DoseStoreError.configurationError,
                               LoopError.connectionError,
                               PumpManagerError.configuration(nil),
                               TestLocalizedError(errorDescription: "StoredDosingDecision.errors.errorDescription",
                                                  failureReason: "StoredDosingDecision.errors.failureReason",
                                                  helpAnchor: "StoredDosingDecision.errors.helpAnchor",
                                                  recoverySuggestion: "StoredDosingDecision.errors.recoverySuggestion")]
        let storedDosingDecision = StoredDosingDecision(date: dateFormatter.date(from: "2020-05-14T22:38:14Z")!,
                                                        insulinOnBoard: insulinOnBoard,
                                                        carbsOnBoard: carbsOnBoard,
                                                        scheduleOverride: scheduleOverride,
                                                        glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                                                        glucoseTargetRangeScheduleApplyingOverrideIfActive: glucoseTargetRangeScheduleApplyingOverrideIfActive,
                                                        predictedGlucose: predictedGlucose,
                                                        predictedGlucoseIncludingPendingInsulin: predictedGlucoseIncludingPendingInsulin,
                                                        lastReservoirValue: lastReservoirValue,
                                                        recommendedTempBasal: recommendedTempBasal,
                                                        recommendedBolus: recommendedBolus,
                                                        pumpManagerStatus: pumpManagerStatus,
                                                        notificationSettings: notificationSettings,
                                                        deviceSettings: deviceSettings,
                                                        errors: errors,
                                                        syncIdentifier: "2A67A303-5203-4CB8-8263-79498265368E")
        try assertStoredDosingDecisionCodable(storedDosingDecision, encodesJSON: """
{
  "carbsOnBoard" : {
    "endDate" : "2020-05-14T23:18:41Z",
    "quantity" : 45.5,
    "quantityUnit" : "g",
    "startDate" : "2020-05-14T22:48:41Z"
  },
  "date" : "2020-05-14T22:38:14Z",
  "deviceSettings" : {
    "batteryLevel" : 0.5,
    "batteryState" : "charging",
    "model" : "Device Model",
    "modelIdentifier" : "Device Model Identifier",
    "name" : "Device Name",
    "systemName" : "Device System Name",
    "systemVersion" : "Device System Version"
  },
  "errors" : [
    {
      "carbStoreError" : "notConfigured"
    },
    {
      "doseStoreError" : "configurationError"
    },
    {
      "loopError" : "connectionError"
    },
    {
      "pumpManagerError" : {
        "configuration" : {

        }
      }
    },
    {
      "unknownError" : {
        "errorDescription" : "StoredDosingDecision.errors.errorDescription",
        "failureReason" : "StoredDosingDecision.errors.failureReason",
        "helpAnchor" : "StoredDosingDecision.errors.helpAnchor",
        "recoverySuggestion" : "StoredDosingDecision.errors.recoverySuggestion"
      }
    }
  ],
  "glucoseTargetRangeSchedule" : {
    "override" : {
      "end" : "2020-05-14T23:12:17Z",
      "start" : "2020-05-14T21:12:17Z",
      "value" : {
        "maxValue" : 115,
        "minValue" : 105
      }
    },
    "rangeSchedule" : {
      "unit" : "mg/dL",
      "valueSchedule" : {
        "items" : [
          {
            "startTime" : 0,
            "value" : {
              "maxValue" : 110,
              "minValue" : 100
            }
          },
          {
            "startTime" : 25200,
            "value" : {
              "maxValue" : 100,
              "minValue" : 90
            }
          },
          {
            "startTime" : 75600,
            "value" : {
              "maxValue" : 120,
              "minValue" : 110
            }
          }
        ],
        "referenceTimeInterval" : 0,
        "repeatInterval" : 86400,
        "timeZone" : {
          "identifier" : "America/Los_Angeles"
        }
      }
    }
  },
  "glucoseTargetRangeScheduleApplyingOverrideIfActive" : {
    "override" : {
      "end" : "2020-05-14T23:12:17Z",
      "start" : "2020-05-14T21:12:17Z",
      "value" : {
        "maxValue" : 115,
        "minValue" : 105
      }
    },
    "rangeSchedule" : {
      "unit" : "mg/dL",
      "valueSchedule" : {
        "items" : [
          {
            "startTime" : 0,
            "value" : {
              "maxValue" : 110,
              "minValue" : 100
            }
          },
          {
            "startTime" : 25200,
            "value" : {
              "maxValue" : 100,
              "minValue" : 90
            }
          },
          {
            "startTime" : 75600,
            "value" : {
              "maxValue" : 120,
              "minValue" : 110
            }
          }
        ],
        "referenceTimeInterval" : 0,
        "repeatInterval" : 86400,
        "timeZone" : {
          "identifier" : "America/Los_Angeles"
        }
      }
    }
  },
  "insulinOnBoard" : {
    "startDate" : "2020-05-14T22:38:26Z",
    "value" : 1.5
  },
  "lastReservoirValue" : {
    "startDate" : "2020-05-14T22:07:19Z",
    "unitVolume" : 113.3
  },
  "notificationSettings" : "\(notificationSettingsBase64)",
  "predictedGlucose" : [
    {
      "quantity" : 123.3,
      "quantityUnit" : "mg/dL",
      "startDate" : "2020-05-14T22:43:15Z"
    },
    {
      "quantity" : 125.5,
      "quantityUnit" : "mg/dL",
      "startDate" : "2020-05-14T22:48:15Z"
    },
    {
      "quantity" : 127.8,
      "quantityUnit" : "mg/dL",
      "startDate" : "2020-05-14T22:53:15Z"
    }
  ],
  "predictedGlucoseIncludingPendingInsulin" : [
    {
      "quantity" : 113.3,
      "quantityUnit" : "mg/dL",
      "startDate" : "2020-05-14T22:43:15Z"
    },
    {
      "quantity" : 115.5,
      "quantityUnit" : "mg/dL",
      "startDate" : "2020-05-14T22:48:15Z"
    },
    {
      "quantity" : 117.8,
      "quantityUnit" : "mg/dL",
      "startDate" : "2020-05-14T22:53:15Z"
    }
  ],
  "pumpManagerStatus" : {
    "basalDeliveryState" : "initiatingTempBasal",
    "bolusState" : "none",
    "device" : {
      "firmwareVersion" : "Device Firmware Version",
      "hardwareVersion" : "Device Hardware Version",
      "localIdentifier" : "Device Local Identifier",
      "manufacturer" : "Device Manufacturer",
      "model" : "Device Model",
      "name" : "Device Name",
      "softwareVersion" : "Device Software Version",
      "udiDeviceIdentifier" : "Device UDI Device Identifier"
    },
    "pumpBatteryChargeRemaining" : 3.5,
    "timeZone" : {
      "identifier" : "America/Los_Angeles"
    }
  },
  "recommendedBolus" : {
    "date" : "2020-05-14T22:38:16Z",
    "recommendation" : {
      "amount" : 1.2,
      "notice" : {
        "predictedGlucoseBelowTarget" : {
          "minGlucose" : {
            "endDate" : "2020-05-14T23:03:15Z",
            "quantity" : 75.5,
            "quantityUnit" : "mg/dL",
            "startDate" : "2020-05-14T23:03:15Z"
          }
        }
      },
      "pendingInsulin" : 0.75
    }
  },
  "recommendedTempBasal" : {
    "date" : "2020-05-14T22:38:15Z",
    "recommendation" : {
      "duration" : 1800,
      "unitsPerHour" : 0.75
    }
  },
  "scheduleOverride" : {
    "context" : "custom",
    "duration" : {
      "finite" : {
        "duration" : 2700
      }
    },
    "enactTrigger" : "local",
    "settings" : {
      "insulinNeedsScaleFactor" : 0.75,
      "targetRangeInMgdl" : {
        "maxValue" : 90,
        "minValue" : 80
      }
    },
    "startDate" : "2020-05-14T22:01:23Z",
    "syncIdentifier" : "238E41EA-9576-4981-A1A4-51E10228584F"
  },
  "syncIdentifier" : "2A67A303-5203-4CB8-8263-79498265368E"
}
"""
        )
    }
    
    private func assertStoredDosingDecisionCodable(_ original: StoredDosingDecision, encodesJSON string: String) throws {
        let data = try encoder.encode(original)
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
        let decoded = try decoder.decode(StoredDosingDecision.self, from: data)
        XCTAssertEqual(decoded, original)
    }
    
    private let dateFormatter = ISO8601DateFormatter()
    
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension StoredDosingDecision: Equatable {
    public static func == (lhs: StoredDosingDecision, rhs: StoredDosingDecision) -> Bool {
        return lhs.date == rhs.date &&
            lhs.insulinOnBoard == rhs.insulinOnBoard &&
            lhs.carbsOnBoard == rhs.carbsOnBoard &&
            lhs.scheduleOverride == rhs.scheduleOverride &&
            lhs.glucoseTargetRangeSchedule == rhs.glucoseTargetRangeSchedule &&
            lhs.glucoseTargetRangeScheduleApplyingOverrideIfActive == rhs.glucoseTargetRangeScheduleApplyingOverrideIfActive &&
            lhs.predictedGlucose == rhs.predictedGlucose &&
            lhs.predictedGlucoseIncludingPendingInsulin == rhs.predictedGlucoseIncludingPendingInsulin &&
            lhs.lastReservoirValue == rhs.lastReservoirValue &&
            lhs.recommendedTempBasal == rhs.recommendedTempBasal &&
            lhs.recommendedBolus == rhs.recommendedBolus &&
            lhs.pumpManagerStatus == rhs.pumpManagerStatus &&
            lhs.notificationSettings == rhs.notificationSettings &&
            lhs.deviceSettings == rhs.deviceSettings &&
            errorsEqual(lhs.errors, rhs.errors) &&
            lhs.syncIdentifier == rhs.syncIdentifier
    }
    
    private static func errorsEqual(_ lhs: [Error]?, _ rhs: [Error]?) -> Bool {
        guard let lhs = lhs else {
            return rhs == nil
        }
        guard let rhs = rhs else {
            return false
        }
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { errorsEqual($0, $1) }
    }
    
    private static func errorsEqual(_ lhs: Error, _ rhs: Error) -> Bool {
        switch (lhs, rhs) {
        case (let lhs as CarbStore.CarbStoreError, let rhs as CarbStore.CarbStoreError):
            return lhs == rhs
        case (let lhs as DoseStore.DoseStoreError, let rhs as DoseStore.DoseStoreError):
            return lhs == rhs
        case (let lhs as LoopError, let rhs as LoopError):
            return lhs == rhs
        case (let lhs as PumpManagerError, let rhs as PumpManagerError):
            return lhs == rhs
        case (let lhs as LocalizedError, let rhs as LocalizedError):
            return lhs.localizedDescription == rhs.localizedDescription &&
                lhs.errorDescription == rhs.errorDescription &&
                lhs.failureReason == rhs.failureReason &&
                lhs.recoverySuggestion == rhs.recoverySuggestion &&
                lhs.helpAnchor == rhs.helpAnchor
        default:
            return lhs.localizedDescription == rhs.localizedDescription
        }
    }
}

extension StoredDosingDecision.LastReservoirValue: Equatable {
    public static func == (lhs: StoredDosingDecision.LastReservoirValue, rhs: StoredDosingDecision.LastReservoirValue) -> Bool {
        return lhs.startDate == rhs.startDate && lhs.unitVolume == rhs.unitVolume
    }
}

extension StoredDosingDecision.TempBasalRecommendationWithDate: Equatable {
    public static func == (lhs: StoredDosingDecision.TempBasalRecommendationWithDate, rhs: StoredDosingDecision.TempBasalRecommendationWithDate) -> Bool {
        return lhs.recommendation == rhs.recommendation && lhs.date == rhs.date
    }
}

extension StoredDosingDecision.BolusRecommendationWithDate: Equatable {
    public static func == (lhs: StoredDosingDecision.BolusRecommendationWithDate, rhs: StoredDosingDecision.BolusRecommendationWithDate) -> Bool {
        return lhs.recommendation == rhs.recommendation && lhs.date == rhs.date
    }
}

fileprivate let notificationSettingsBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V" +
    "5ZWRBcmNoaXZlctEICVRyb290gAGjCwwgVSRudWxs3g0ODxAREhMUFRYXGBkaGxsbGxscHBwdHhsfHBtcYmFkZ2VTZXR0aW5nXxATYXV0aG9yaXphdGlvblN0YXR" +
    "1c1xzb3VuZFNldHRpbmdfEBlub3RpZmljYXRpb25DZW50ZXJTZXR0aW5nXxAUY3JpdGljYWxBbGVydFNldHRpbmdfEBNzaG93UHJldmlld3NTZXR0aW5nXxAPZ3J" +
    "vdXBpbmdTZXR0aW5nXmNhclBsYXlTZXR0aW5nXxAfcHJvdmlkZXNBcHBOb3RpZmljYXRpb25TZXR0aW5nc1YkY2xhc3NfEBFsb2NrU2NyZWVuU2V0dGluZ1phbGV" +
    "ydFN0eWxlXxATYW5ub3VuY2VtZW50U2V0dGluZ1xhbGVydFNldHRpbmcQAhAACIACEAHSISIjJFokY2xhc3NuYW1lWCRjbGFzc2VzXxAWVU5Ob3RpZmljYXRpb25" +
    "TZXR0aW5nc6IlJl8QFlVOTm90aWZpY2F0aW9uU2V0dGluZ3NYTlNPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAFcAXQB6AIcAnQCqAMYA3QDzAQUBFAE2AT0" +
    "BUQFcAXIBfwGBAYMBhAGGAYgBjQGYAaEBugG9AdYAAAAAAAACAQAAAAAAAAAnAAAAAAAAAAAAAAAAAAAB3w=="
fileprivate let notificationSettingsData = Data(base64Encoded: notificationSettingsBase64)!
fileprivate let notificationSettings = try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(notificationSettingsData) as! UNNotificationSettings
