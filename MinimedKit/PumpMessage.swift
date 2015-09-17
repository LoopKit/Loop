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
    public let address: NSData
    public let messageType: MessageType
    public let messageBody: MessageBody

    public init(packetType: PacketType, address: String, messageType: MessageType, messageBody: MessageBody) {
        self.packetType = packetType
        self.address = NSData(hexadecimalString: address)!
        self.messageType = messageType
        self.messageBody = messageBody
    }

    public init?(rxData: NSData) {
        if rxData.length >= 7, let
            packetType = PacketType(rawValue: rxData[0]),
            messageType = MessageType(rawValue: rxData[4]),
            messageBody = messageType.bodyType.init(rxData: rxData.subdataWithRange(NSRange(5..<rxData.length - 1)))
        {
            self.packetType = packetType
            self.address = rxData.subdataWithRange(NSRange(1...3))
            self.messageType = messageType
            self.messageBody = messageBody
        } else {
            return nil
        }
    }

    public var txData: NSData {
        var buffer = [UInt8]()

        buffer.append(packetType.rawValue)
        buffer += address[0...2]
        buffer.append(messageType.rawValue)

        let data = NSMutableData(bytes: &buffer, length: buffer.count)

        data.appendData(messageBody.txData)

        return NSData(data: data)
    }
}

