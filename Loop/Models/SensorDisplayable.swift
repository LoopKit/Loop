//
//  SensorDisplayable.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


protocol SensorDisplayable {
    /// Returns whether the current state is valid
    var isStateValid: Bool { get }

    /// Describes the state of the sensor in the current localization
    var stateDescription: String { get }

    /// Enumerates the trend of the sensor values
    var trendType: GlucoseTrend? { get }

    /// Returns wheter the data is from a locally-connected device
    var isLocal: Bool { get }
}


extension SensorDisplayable {
    var stateDescription: String {
        if isStateValid {
            return NSLocalizedString("OK", comment: "Sensor state description for the valid state")
        } else {
            return NSLocalizedString("Needs Attention", comment: "Sensor state description for the non-valid state")
        }
    }
}
