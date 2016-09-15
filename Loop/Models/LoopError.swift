//
//  LoopError.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//


enum LoopError: Error {
    // Failure during device communication
    case communicationError

    // Missing or unexpected configuration values
    case configurationError

    // No connected devices, or failure during device connection
    case connectionError

    // Missing required data to perform an action
    case missingDataError(String)

    // Out-of-date required data to perform an action
    case staleDataError(String)
}
