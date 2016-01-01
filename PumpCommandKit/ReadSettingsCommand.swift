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

class ReadSettingsCommand: NSObject {

    private let address: String

    private let message: PumpMessage

    init(address: String) {
        self.address = address

        self.message = PumpMessage(packetType: MinimedKit.PacketType.Carelink, address: address, messageType: .ReadSettings, messageBody: CarelinkShortMessageBody())

        super.init()
    }

    func packetType() -> RileyLinkKit.PacketType {
        return .Carelink
    }

    func packetAddress() -> String {
        return address
    }
}
