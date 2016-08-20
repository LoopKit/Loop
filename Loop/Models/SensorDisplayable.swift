//
//  SensorDisplayable.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//


protocol SensorDisplayable {
    // Describes the state of the sensor in the current localization
    var stateDescription: String { get }

    /// Enumerates the trend of the sensor values
    var trendType: GlucoseTrend? { get }
}
