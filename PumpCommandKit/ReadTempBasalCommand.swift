//
//  ReadTempBasalCommand.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import MinimedKit


class ReadTempBasalCommand {

    let message: PumpMessage
    let response: MessageType = .ReadTempBasal

    init(address: String) {
        message = PumpMessage(packetType: .Carelink, address: address, messageType: .ReadTempBasal, messageBody: CarelinkShortMessageBody())
    }

}