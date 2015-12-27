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

class PowerOnCommand: NSObject, MessageSendOperationGroup {

    private var operations: [RileyLinkKit.MessageSendOperation] = []

    var duration: NSTimeInterval

    init(duration: NSTimeInterval, address: String, device: RileyLinkBLEDevice) {

        self.duration = duration

        let requestMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .PowerOn, messageBody: CarelinkShortMessageBody())

        let requestOperation = MessageSendOperation(device: device, message: MessageBase(data: requestMessage.txData), timeout: 10, completionHandler: nil)

        requestOperation.responseMessageType = RileyLinkKit.MessageType.MESSAGE_TYPE_ACK

        requestOperation.repeatInterval = 1.0/12.0

        operations.append(requestOperation)

        let argsMessage = PumpMessage(packetType: .Carelink, address: address, messageType: .PowerOn, messageBody: PowerOnCarelinkMessageBody(duration: duration))

        let argsOperation = MessageSendOperation(device: device, message: MessageBase(data: argsMessage.txData), timeout: 10, completionHandler: nil)

        argsOperation.responseMessageType = RileyLinkKit.MessageType.MESSAGE_TYPE_ACK

        operations.append(argsOperation)

        super.init()
    }

    // MARK: - MessageSendOperationGroup

    func packetType() -> RileyLinkKit.PacketType {
        return .Carelink
    }

    func messageOperations() -> [MessageSendOperation] {
        return operations
    }
}
