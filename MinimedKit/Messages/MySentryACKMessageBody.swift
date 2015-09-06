//
//  MySentryAckMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/4/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


/// Describes an ACK message sent by a MySentry device in response to pump status messages.
/// a2 350535 06 59 000695 00 04000000 e2
public struct MySentryAckMessageBody: MessageBody {
    public static let length = 9
    static var MessageCounter: UInt8 = 0

    let mySentryID: [UInt8]
    let responseMessageTypes: [MessageType]

    public init(mySentryID: [UInt8], responseMessageTypes: [MessageType]) {
        assert(mySentryID.count == 3)
        assert(responseMessageTypes.count <= 4)

        self.mySentryID = mySentryID
        self.responseMessageTypes = responseMessageTypes
    }

    public init?(rxData: NSData) {
        if rxData.length == self.dynamicType.length {
            mySentryID = rxData[1...3]
            responseMessageTypes = rxData[5...8].flatMap({ MessageType(rawValue: $0) })
        } else {
            return nil
        }
    }

    public var txData: NSData {
        var buffer = self.dynamicType.emptyBuffer

        buffer[0] = self.dynamicType.MessageCounter++
        buffer.replaceRange(1...3, with: mySentryID)

        buffer.replaceRange(5..<5 + responseMessageTypes.count, with: responseMessageTypes.map({ $0.rawValue }))

        return NSData(bytes: &buffer, length: buffer.count)
    }
}
