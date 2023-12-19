//
//  SettingsManager.swift
//  LoopTests
//
//  Created by Pete Schwamb on 12/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
@testable import Loop

@MainActor
final class SettingsManagerTests: XCTestCase {


    func testChangingMaxBasalUpdatesLoopData() async {

        let persistenceController = PersistenceController.mock()

        let settingsManager = SettingsManager(cacheStore: persistenceController, expireAfter: .days(1), alertMuter: AlertMuter())

        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: nil) { _ in
            exp.fulfill()
        }

        settingsManager.mutateLoopSettings { $0.maximumBasalRatePerHour = 2.0 }

        await fulfillment(of: [exp], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }


}
