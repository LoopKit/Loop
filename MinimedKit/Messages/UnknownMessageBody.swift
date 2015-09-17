//
//  UnknownMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/16/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public struct UnknownMessageBody: MessageBody, DictionaryRepresentable {
    public static var length = 0

    let rxData: NSData

    public init?(rxData: NSData) {
        self.rxData = rxData
    }

    public var txData: NSData {
        return rxData
    }

    public var dictionaryRepresentation: [String: AnyObject] {
        return ["rawData": rxData]
    }
}