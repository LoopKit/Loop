//
//  SetTempBasalCommand.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import MinimedKit


class SetTempBasalCommand: TwoStepCommand {

    let firstMessage: PumpMessage
    let firstResponse: MessageType
    let secondMessage: PumpMessage
    let secondResponse: MessageType

    init(unitsPerHour: Double, duration: NSTimeInterval, address: String) {

        firstMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .SetTempBasal, messageBody: CarelinkShortMessageBody())
        firstResponse = .PumpStatusAck
        secondMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .SetTempBasal, messageBody: SetTempBasalCarelinkMessageBody(unitsPerHour: unitsPerHour, duration: duration))
        secondResponse = .PumpStatusAck
    }
    
}