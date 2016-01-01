//
//  PowerOnCommand.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import MinimedKit
import RileyLinkKit

class PowerOnCommand: NSObject {

    private let address: String

    private var messages = [PumpMessage]()

    var duration: NSTimeInterval

    init(duration: NSTimeInterval, address: String) {

        self.duration = duration

        self.address = address

        let requestMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .PowerOn, messageBody: CarelinkShortMessageBody())

        let argsMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .PowerOn, messageBody: PowerOnCarelinkMessageBody(duration: duration))

        messages.append(requestMessage)
        messages.append(argsMessage)

        super.init()
    }

    func packetType() -> RileyLinkKit.PacketType {
        return .Carelink
    }

    func packetAddress() -> String {
        return address
    }
}
