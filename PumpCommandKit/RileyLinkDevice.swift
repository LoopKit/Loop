//
//  RileyLinkDevice.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import MinimedKit
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

    /**
     Send a temp basal using the existing PumpOps infrastructure

     - parameter unitsPerHour:      The rate to deliver, in Units per hour
     - parameter duration:          The length of time to run the dose
     - parameter completionHandler: A closure called after the dose command was run. The closure takes two arguments:
        - success:     Whether the command was successfully executed
        - doseMessage: The pump response message, describing the new temp basal
        - error:       An error describing why the command failed to execute
     */
    func sendTempBasalDose(unitsPerHour: Double, duration: NSTimeInterval, completionHandler: (success: Bool, doseMessage: PumpMessage?, error: CommandError?) -> Void) {
        guard let pumpID = pumpState?.pumpId else {
            completionHandler(success: false, doseMessage: nil, error: .ConfigurationError)
            return
        }

        let writeCommand = ChangeTempBasalCommand(unitsPerHour: unitsPerHour, duration: duration, address: pumpID)
        let readCommand = ReadTempBasalCommand(address: pumpID)

        sendTempBasalMessage(writeCommand.firstMessage.txData, secondMessage: writeCommand.secondMessage.txData, thirdMessage: readCommand.message.txData) { (response, error) -> Void in
            if let response = response, message = PumpMessage(rxData: response), body = message.messageBody as? ReadTempBasalCarelinkMessageBody {
                let success = body.timeRemaining == duration

                completionHandler(success: success, doseMessage: message, error: success ? nil : .CommunicationError("Dose did not verify"))
            } else {
                completionHandler(success: false, doseMessage: nil, error: .CommunicationError(error ?? ""))
            }
        }
    }

    func changeTime(completionHandler: (success: Bool, error: CommandError?) -> Void) {
        guard let pumpID = pumpState?.pumpId else {
            completionHandler(success: false, error: .ConfigurationError)
            return
        }

        let firstMessage = PumpMessage(packetType: .Carelink, address: pumpID, messageType: .ChangeTime, messageBody: CarelinkShortMessageBody())

        let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!

        sendChangeTimeMessage(firstMessage.txData,
            secondMessageGenerator: { () -> NSData in
                let components = calendar.components([.Year, .Month, .Day, .Hour, .Minute, .Second], fromDate: NSDate())

                return PumpMessage(packetType: .Carelink, address: pumpID, messageType: .ChangeTime, messageBody: ChangeTimeCarelinkMessageBody(dateComponents: components)!).txData
            }
        ) { (response, error) -> Void in
            if response != nil {
                completionHandler(success: true, error: nil)

                NSNotificationCenter.defaultCenter().postNotificationName(RileyLinkDeviceDidChangeTimeNotification, object: self, userInfo: [RileyLinkDeviceTimeKey: NSDate()])
            } else {
                completionHandler(success: false, error: .CommunicationError(error ?? ""))
            }
        }
    }

    private func sendTwoStepCommand(command: TwoStepCommand, completionHandler: (response: NSData?, error: CommandError?) -> Void) {

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