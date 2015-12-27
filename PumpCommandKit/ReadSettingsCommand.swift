//
//  ReadSettingsCommand.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import MinimedKit
import RileyLinkKit

class ReadSettingsCommand: NSObject, MessageSendOperationGroup {

    private let messageOperation: MessageSendOperation

    init(address: String, device: RileyLinkBLEDevice) {
        let message = PumpMessage(packetType: MinimedKit.PacketType.Carelink, address: address, messageType: .ReadSettings, messageBody: CarelinkShortMessageBody())

        messageOperation = MessageSendOperation(device: device, message: MessageBase(data: message.txData), timeout: 10, completionHandler: nil)
        messageOperation.responseMessageType = RileyLinkKit.MessageType.MESSAGE_TYPE_READ_SETTINGS

        super.init()
    }

    var result: PumpMessage? {
        if let data = messageOperation.responsePacket?.data {
            return PumpMessage(rxData: data)
        } else {
            return nil
        }
    }

    // MARK: - MessageSendOperationGroup

    func packetType() -> RileyLinkKit.PacketType {
        return .Carelink
    }

    func messageOperations() -> [MessageSendOperation] {
        return [messageOperation]
    }
}
