//
//  LoopError.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//


enum LoopError: ErrorType {
    // Failure during device communication
    case CommunicationError

    // Missing or unexpected configuration values
    case ConfigurationError

    // No connected devices, or failure during device connection
    case ConnectionError

    // Missing required data to perform an action
    case MissingDataError(String)

    // Out-of-date required data to perform an action
    case StaleDataError(String)
}
