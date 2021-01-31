//
//  DosingDecisionStoreTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 5/12/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit

@testable import Loop
@testable import LoopKit

class DosingDecisionStorePersistenceTests: PersistenceControllerTestCase {
    func testSettingsObjectEncodable() throws {
        cacheStore.managedObjectContext.performAndWait {
            do {
                let object = DosingDecisionObject(context: cacheStore.managedObjectContext)
                object.data = try PropertyListEncoder().encode(StoredDosingDecision.test)
                object.date = dateFormatter.date(from: "2100-01-02T03:03:00Z")!
                object.modificationCounter = 123
                try assertDosingDecisionObjectEncodable(object, encodesJSON: """
{
  "data" : {
    "automaticDoseRecommendation" : {
      "date" : "2020-05-14T22:38:15Z",
      "recommendation" : {
        "basalAdjustment" : {
          "duration" : 1800,
          "unitsPerHour" : 0.75
        },
        "bolusUnits" : 0
      }
    },
    "carbEntry" : {
      "absorptionTime" : 18000,
      "createdByCurrentApp" : true,
      "foodType" : "Pizza",
      "provenanceIdentifier" : "com.loopkit.loop",
      "quantity" : 29,
      "startDate" : "2020-01-02T03:00:23Z",
      "syncIdentifier" : "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
      "syncVersion" : 2,
      "userCreatedDate" : "2020-05-14T22:06:12Z",
      "userUpdatedDate" : "2020-05-14T22:07:32Z",
      "uuid" : "135CDABE-9343-7242-4233-1020384789AE"
    },
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
    "effectiveGlucoseTargetRangeSchedule" : {
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
    "insulinOnBoard" : {
      "startDate" : "2020-05-14T22:38:26Z",
      "value" : 1.5
    },
    "lastReservoirValue" : {
      "startDate" : "2020-05-14T22:07:19Z",
      "unitVolume" : 113.3
    },
    "manualGlucose" : {
      "endDate" : "2020-05-14T22:09:00Z",
      "quantity" : 153,
      "quantityUnit" : "mg/dL",
      "startDate" : "2020-05-14T22:09:00Z"
    },
    "notificationSettings" : {
      "alertSetting" : "disabled",
      "alertStyle" : "banner",
      "announcementSetting" : "enabled",
      "authorizationStatus" : "authorized",
      "badgeSetting" : "enabled",
      "carPlaySetting" : "notSupported",
      "criticalAlertSetting" : "enabled",
      "lockScreenSetting" : "disabled",
      "notificationCenterSetting" : "notSupported",
      "providesAppNotificationSettings" : true,
      "showPreviewsSetting" : "whenAuthenticated",
      "soundSetting" : "enabled"
    },
    "originalCarbEntry" : {
      "absorptionTime" : 18000,
      "createdByCurrentApp" : true,
      "foodType" : "Pizza",
      "provenanceIdentifier" : "com.loopkit.loop",
      "quantity" : 19,
      "startDate" : "2020-01-02T03:00:23Z",
      "syncIdentifier" : "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
      "syncVersion" : 1,
      "userCreatedDate" : "2020-05-14T22:06:12Z",
      "uuid" : "18CF3948-0B3D-4B12-8BFE-14986B0E6784"
    },
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
      "bolusState" : "noBolus",
      "deliveryIsUncertain" : false,
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
      "insulinType" : 0,
      "pumpBatteryChargeRemaining" : 3.5,
      "pumpLifecycleProgress" : {
        "percentComplete" : 0.5,
        "progressState" : "warning"
      },
      "pumpStatusHighlight" : {
        "imageName" : "test.image",
        "localizedMessage" : "Test message",
        "state" : "normalPump"
      },
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
    "requestedBolus" : 0.80000000000000004,
    "scheduleOverride" : {
      "actualEnd" : {
        "type" : "natural"
      },
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
  },
  "date" : "2100-01-02T03:03:00Z",
  "modificationCounter" : 123
}
"""
                )
            } catch let error {
                XCTFail("Unexpected failure: \(error)")
            }
        }
    }

    private func assertDosingDecisionObjectEncodable(_ original: DosingDecisionObject, encodesJSON string: String) throws {
        let data = try encoder.encode(original)
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
    }

    private let dateFormatter = ISO8601DateFormatter()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

class DosingDecisionStoreCriticalEventLogTests: PersistenceControllerTestCase {
    var dosingDecisionStore: DosingDecisionStore!
    var outputStream: MockOutputStream!
    var progress: Progress!
    
    override func setUp() {
        super.setUp()
        
        let dosingDecisions = [StoredDosingDecision(date: dateFormatter.date(from: "2100-01-02T03:08:00Z")!, syncIdentifier: "18CF3948-0B3D-4B12-8BFE-14986B0E6784"),
                               StoredDosingDecision(date: dateFormatter.date(from: "2100-01-02T03:10:00Z")!, syncIdentifier: "C86DEB61-68E9-464E-9DD5-96A9CB445FD3"),
                               StoredDosingDecision(date: dateFormatter.date(from: "2100-01-02T03:04:00Z")!, syncIdentifier: "2B03D96C-6F5D-4140-99CD-80C3E64D6010"),
                               StoredDosingDecision(date: dateFormatter.date(from: "2100-01-02T03:06:00Z")!, syncIdentifier: "FF1C4F01-3558-4FB2-957E-FA1522C4735E"),
                               StoredDosingDecision(date: dateFormatter.date(from: "2100-01-02T03:02:00Z")!, syncIdentifier: "71B699D7-0E8F-4B13-B7A1-E7751EB78E74")]
        
        dosingDecisionStore = DosingDecisionStore(store: cacheStore, expireAfter: .hours(1))

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        dosingDecisionStore.addStoredDosingDecisions(dosingDecisions: dosingDecisions) { error in
            XCTAssertNil(error)
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
        
        outputStream = MockOutputStream()
        progress = Progress()
    }
    
    override func tearDown() {
        dosingDecisionStore = nil
        
        super.tearDown()
    }
    
    func testExportProgressTotalUnitCount() {
        switch dosingDecisionStore.exportProgressTotalUnitCount(startDate: dateFormatter.date(from: "2100-01-02T03:03:00Z")!,
                                                                endDate: dateFormatter.date(from: "2100-01-02T03:09:00Z")!) {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let progressTotalUnitCount):
            XCTAssertEqual(progressTotalUnitCount, 3 * 33)
        }
    }
    
    func testExportProgressTotalUnitCountEmpty() {
        switch dosingDecisionStore.exportProgressTotalUnitCount(startDate: dateFormatter.date(from: "2100-01-02T03:00:00Z")!,
                                                                endDate: dateFormatter.date(from: "2100-01-02T03:01:00Z")!) {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let progressTotalUnitCount):
            XCTAssertEqual(progressTotalUnitCount, 0)
        }
    }
    
    func testExport() {
        XCTAssertNil(dosingDecisionStore.export(startDate: dateFormatter.date(from: "2100-01-02T03:03:00Z")!,
                                                endDate: dateFormatter.date(from: "2100-01-02T03:09:00Z")!,
                                                to: outputStream,
                                                progress: progress))
        XCTAssertEqual(outputStream.string, """
[
{"data":{"date":"2100-01-02T03:08:00.000Z","syncIdentifier":"18CF3948-0B3D-4B12-8BFE-14986B0E6784"},"date":"2100-01-02T03:08:00.000Z","modificationCounter":1},
{"data":{"date":"2100-01-02T03:04:00.000Z","syncIdentifier":"2B03D96C-6F5D-4140-99CD-80C3E64D6010"},"date":"2100-01-02T03:04:00.000Z","modificationCounter":3},
{"data":{"date":"2100-01-02T03:06:00.000Z","syncIdentifier":"FF1C4F01-3558-4FB2-957E-FA1522C4735E"},"date":"2100-01-02T03:06:00.000Z","modificationCounter":4}
]
"""
        )
        XCTAssertEqual(progress.completedUnitCount, 3 * 33)
    }
    
    func testExportEmpty() {
        XCTAssertNil(dosingDecisionStore.export(startDate: dateFormatter.date(from: "2100-01-02T03:00:00Z")!,
                                                endDate: dateFormatter.date(from: "2100-01-02T03:01:00Z")!,
                                                to: outputStream,
                                                progress: progress))
        XCTAssertEqual(outputStream.string, "[]")
        XCTAssertEqual(progress.completedUnitCount, 0)
    }
    
    func testExportCancelled() {
        progress.cancel()
        XCTAssertEqual(dosingDecisionStore.export(startDate: dateFormatter.date(from: "2100-01-02T03:03:00Z")!,
                                                  endDate: dateFormatter.date(from: "2100-01-02T03:09:00Z")!,
                                                  to: outputStream,
                                                  progress: progress) as? CriticalEventLogError, CriticalEventLogError.cancelled)
    }
    
    private let dateFormatter = ISO8601DateFormatter()
}

class StoredDosingDecisionCodableTests: XCTestCase {
    func testCodable() throws {
        try assertStoredDosingDecisionCodable(StoredDosingDecision.test, encodesJSON: """
{
  "automaticDoseRecommendation" : {
    "date" : "2020-05-14T22:38:15Z",
    "recommendation" : {
      "basalAdjustment" : {
        "duration" : 1800,
        "unitsPerHour" : 0.75
      },
      "bolusUnits" : 0
    }
  },
  "carbEntry" : {
    "absorptionTime" : 18000,
    "createdByCurrentApp" : true,
    "foodType" : "Pizza",
    "provenanceIdentifier" : "com.loopkit.loop",
    "quantity" : 29,
    "startDate" : "2020-01-02T03:00:23Z",
    "syncIdentifier" : "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
    "syncVersion" : 2,
    "userCreatedDate" : "2020-05-14T22:06:12Z",
    "userUpdatedDate" : "2020-05-14T22:07:32Z",
    "uuid" : "135CDABE-9343-7242-4233-1020384789AE"
  },
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
  "effectiveGlucoseTargetRangeSchedule" : {
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
  "insulinOnBoard" : {
    "startDate" : "2020-05-14T22:38:26Z",
    "value" : 1.5
  },
  "lastReservoirValue" : {
    "startDate" : "2020-05-14T22:07:19Z",
    "unitVolume" : 113.3
  },
  "manualGlucose" : {
    "endDate" : "2020-05-14T22:09:00Z",
    "quantity" : 153,
    "quantityUnit" : "mg/dL",
    "startDate" : "2020-05-14T22:09:00Z"
  },
  "notificationSettings" : {
    "alertSetting" : "disabled",
    "alertStyle" : "banner",
    "announcementSetting" : "enabled",
    "authorizationStatus" : "authorized",
    "badgeSetting" : "enabled",
    "carPlaySetting" : "notSupported",
    "criticalAlertSetting" : "enabled",
    "lockScreenSetting" : "disabled",
    "notificationCenterSetting" : "notSupported",
    "providesAppNotificationSettings" : true,
    "showPreviewsSetting" : "whenAuthenticated",
    "soundSetting" : "enabled"
  },
  "originalCarbEntry" : {
    "absorptionTime" : 18000,
    "createdByCurrentApp" : true,
    "foodType" : "Pizza",
    "provenanceIdentifier" : "com.loopkit.loop",
    "quantity" : 19,
    "startDate" : "2020-01-02T03:00:23Z",
    "syncIdentifier" : "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
    "syncVersion" : 1,
    "userCreatedDate" : "2020-05-14T22:06:12Z",
    "uuid" : "18CF3948-0B3D-4B12-8BFE-14986B0E6784"
  },
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
    "bolusState" : "noBolus",
    "deliveryIsUncertain" : false,
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
    "insulinType" : 0,
    "pumpBatteryChargeRemaining" : 3.5,
    "pumpLifecycleProgress" : {
      "percentComplete" : 0.5,
      "progressState" : "warning"
    },
    "pumpStatusHighlight" : {
      "imageName" : "test.image",
      "localizedMessage" : "Test message",
      "state" : "normalPump"
    },
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
  "requestedBolus" : 0.80000000000000004,
  "scheduleOverride" : {
    "actualEnd" : {
      "type" : "natural"
    },
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
            lhs.effectiveGlucoseTargetRangeSchedule == rhs.effectiveGlucoseTargetRangeSchedule &&
            lhs.predictedGlucose == rhs.predictedGlucose &&
            lhs.predictedGlucoseIncludingPendingInsulin == rhs.predictedGlucoseIncludingPendingInsulin &&
            lhs.lastReservoirValue == rhs.lastReservoirValue &&
            lhs.automaticDoseRecommendation == rhs.automaticDoseRecommendation &&
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

extension StoredDosingDecision.AutomaticDoseRecommendationWithDate: Equatable {
    public static func == (lhs: StoredDosingDecision.AutomaticDoseRecommendationWithDate, rhs: StoredDosingDecision.AutomaticDoseRecommendationWithDate) -> Bool {
        return lhs.recommendation == rhs.recommendation && lhs.date == rhs.date
    }
}

extension StoredDosingDecision.BolusRecommendationWithDate: Equatable {
    public static func == (lhs: StoredDosingDecision.BolusRecommendationWithDate, rhs: StoredDosingDecision.BolusRecommendationWithDate) -> Bool {
        return lhs.recommendation == rhs.recommendation && lhs.date == rhs.date
    }
}

fileprivate extension StoredDosingDecision {
    static var test: StoredDosingDecision {
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
        let effectiveGlucoseTargetRangeSchedule = GlucoseRangeSchedule(rangeSchedule: DailyQuantitySchedule(unit: .milligramsPerDeciliter,
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
        let manualGlucose = SimpleGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T22:09:00Z")!,
                                               quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 153))
        let originalCarbEntry = StoredCarbEntry(uuid: UUID(uuidString: "18CF3948-0B3D-4B12-8BFE-14986B0E6784")!,
                                                provenanceIdentifier: "com.loopkit.loop",
                                                syncIdentifier: "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
                                                syncVersion: 1,
                                                startDate: dateFormatter.date(from: "2020-01-02T03:00:23Z")!,
                                                quantity: HKQuantity(unit: .gram(), doubleValue: 19),
                                                foodType: "Pizza",
                                                absorptionTime: .hours(5),
                                                createdByCurrentApp: true,
                                                userCreatedDate: dateFormatter.date(from: "2020-05-14T22:06:12Z")!,
                                                userUpdatedDate: nil)
        let carbEntry = StoredCarbEntry(uuid: UUID(uuidString: "135CDABE-9343-7242-4233-1020384789AE")!,
                                        provenanceIdentifier: "com.loopkit.loop",
                                        syncIdentifier: "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
                                        syncVersion: 2,
                                        startDate: dateFormatter.date(from: "2020-01-02T03:00:23Z")!,
                                        quantity: HKQuantity(unit: .gram(), doubleValue: 29),
                                        foodType: "Pizza",
                                        absorptionTime: .hours(5),
                                        createdByCurrentApp: true,
                                        userCreatedDate: dateFormatter.date(from: "2020-05-14T22:06:12Z")!,
                                        userUpdatedDate: dateFormatter.date(from: "2020-05-14T22:07:32Z")!)
        let automaticDosingRecommendation = StoredDosingDecision.AutomaticDoseRecommendationWithDate(
            recommendation: AutomaticDoseRecommendation(
                basalAdjustment: TempBasalRecommendation(
                    unitsPerHour: 0.75,
                    duration: .minutes(30)),
                bolusUnits: 0),
            date: dateFormatter.date(from: "2020-05-14T22:38:15Z")!)
        
        let recommendedBolus = StoredDosingDecision.BolusRecommendationWithDate(recommendation: ManualBolusRecommendation(amount: 1.2,
                                                                                                                    pendingInsulin: 0.75,
                                                                                                                    notice: .predictedGlucoseBelowTarget(minGlucose: PredictedGlucoseValue(startDate: dateFormatter.date(from: "2020-05-14T23:03:15Z")!,
                                                                                                                                                                                           quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 75.5)))),
                                                                                date: dateFormatter.date(from: "2020-05-14T22:38:16Z")!)
        let requestedBolus = 0.8
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
                                                  bolusState: .noBolus,
                                                  insulinType: .novolog,
                                                  pumpStatusHighlight: PumpManagerStatus.PumpStatusHighlight(localizedMessage: "Test message",
                                                                                                             imageName: "test.image",
                                                                                                             state: .normalPump),
                                                  pumpLifecycleProgress: PumpManagerStatus.PumpLifecycleProgress(percentComplete: 0.5,
                                                                                                                 progressState: .warning))
        let notificationSettings = NotificationSettings(authorizationStatus: .authorized,
                                                        soundSetting: .enabled,
                                                        badgeSetting: .enabled,
                                                        alertSetting: .disabled,
                                                        notificationCenterSetting: .notSupported,
                                                        lockScreenSetting: .disabled,
                                                        carPlaySetting: .notSupported,
                                                        alertStyle: .banner,
                                                        showPreviewsSetting: .whenAuthenticated,
                                                        criticalAlertSetting: .enabled,
                                                        providesAppNotificationSettings: true,
                                                        announcementSetting: .enabled)
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
        return StoredDosingDecision(date: dateFormatter.date(from: "2020-05-14T22:38:14Z")!,
                                    insulinOnBoard: insulinOnBoard,
                                    carbsOnBoard: carbsOnBoard,
                                    scheduleOverride: scheduleOverride,
                                    glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                                    effectiveGlucoseTargetRangeSchedule: effectiveGlucoseTargetRangeSchedule,
                                    predictedGlucose: predictedGlucose,
                                    predictedGlucoseIncludingPendingInsulin: predictedGlucoseIncludingPendingInsulin,
                                    lastReservoirValue: lastReservoirValue,
                                    manualGlucose: manualGlucose,
                                    originalCarbEntry: originalCarbEntry,
                                    carbEntry: carbEntry,
                                    automaticDoseRecommendation: automaticDosingRecommendation,
                                    recommendedBolus: recommendedBolus,
                                    requestedBolus: requestedBolus,
                                    pumpManagerStatus: pumpManagerStatus,
                                    notificationSettings: notificationSettings,
                                    deviceSettings: deviceSettings,
                                    errors: errors,
                                    syncIdentifier: "2A67A303-5203-4CB8-8263-79498265368E")
    }

    private static let dateFormatter = ISO8601DateFormatter()
}
