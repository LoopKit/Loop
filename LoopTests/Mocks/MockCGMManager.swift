//
//  MockCGMManager.swift
//  LoopTests
//
//  Created by Pete Schwamb on 10/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class MockCGMManager: CGMManager {
    var inSignalLoss: Bool = false
    
    var isInoperable: Bool = false
    
    var cgmManagerDelegate: LoopKit.CGMManagerDelegate?

    var providesBLEHeartbeat: Bool = false

    var managedDataInterval: TimeInterval?

    var shouldSyncToRemoteService: Bool = true

    var glucoseDisplay: LoopKit.GlucoseDisplayable?

    var cgmManagerStatus: LoopKit.CGMManagerStatus {
        return CGMManagerStatus(hasValidSensorSession: true, device: nil)
    }

    func fetchNewDataIfNeeded(_ completion: @escaping (LoopKit.CGMReadingResult) -> Void) {
        completion(.noData)
    }

    var localizedTitle: String = "MockCGMManager"

    init() {
    }

    required init?(rawState: RawStateValue) {
    }

    var rawState: RawStateValue {
        return [:]
    }

    var isOnboarded: Bool = true

    var debugDescription: String = "MockCGMManager"

    func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier) async throws { }

    func getSoundBaseURL() -> URL? {
        return nil
    }

    func getSounds() -> [LoopKit.Alert.Sound] {
        return []
    }

    var pluginIdentifier: String = "MockCGMManager"

}
