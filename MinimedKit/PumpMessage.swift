//
//  PumpMessage.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/2/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public struct PumpMessage {
    public let packetType: PacketType
    public let address: String
    public let messageType: MessageType

    public init?(data: NSData) {
        if data.length >= 7, let
            packetType = PacketType(rawValue: data[0]),
            messageType = MessageType(rawValue: data[4])
        {
            self.packetType = packetType
            self.address = data.subdataWithRange(NSRange(1...3)).hexadecimalString
            self.messageType = messageType
        } else {
            return nil
        }
    }
}