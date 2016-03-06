//
//  RileyLinkDevice.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import RileyLinkKit


enum CommandError: ErrorType {
    case ConfigurationError
    case CommunicationError(String)
}


extension RileyLinkDevice {
    /**
     Send a bolus using the existing PumpOps infrastructure.
     
     *Note: This assumes a X23 size and greater. Do not use on a live pump!*

     - parameter units:             The number of units to bolus
     - parameter completionHandler: A closure called after the dose command was run. The closure takes two arguments:
        - success: Whether the command was successfully executed
        - error:   An error describing why the command failed to execute
     */
    func sendBolusDose(units: Double, completionHandler: (success: Bool, error: CommandError?) -> Void) {

        guard let pumpID = pumpState?.pumpId else {
            completionHandler(success: false, error: .ConfigurationError)
            return
        }

        let command = BolusCommand(units: units, address: pumpID)

        sendTwoStepCommand(command) { (response, error) -> Void in
            if response != nil {
                completionHandler(success: true, error: nil)
            } else {
                completionHandler(success: false, error: error)
            }
        }
    }

    func sendTwoStepCommand(command: TwoStepCommand, completionHandler: (response: NSData?, error: CommandError?) -> Void) {

        runCommandWithShortMessage(command.firstMessage.txData,
            firstResponse: command.firstResponse.rawValue,
            secondMessage: command.secondMessage.txData,
            secondResponse: command.secondResponse.rawValue)
        { (response, error) -> Void in
            if response != nil {
                completionHandler(response: response, error: nil)
            } else {
                completionHandler(response: nil, error: .CommunicationError(error ?? ""))
            }
        }

    }
}