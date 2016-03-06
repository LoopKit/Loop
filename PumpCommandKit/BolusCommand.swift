//
//  BolusCommand.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import MinimedKit


class BolusCommand {

    let firstMessage: PumpMessage
    let firstResponse: MessageType
    let secondMessage: PumpMessage
    let secondResponse: MessageType

    init(units: Double, address: String) {

        firstMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .Bolus, messageBody: CarelinkShortMessageBody())
        firstResponse = .PumpStatusAck
        secondMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .Bolus, messageBody: BolusCarelinkMessageBody(units: units))
        secondResponse = .PumpStatusAck

    }
    
}