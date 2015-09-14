//
//  MessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/4/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public protocol MessageBody {
    static var length: Int {
        get
    }

    init?(rxData: NSData)

    var txData: NSData {
        get
    }
}


extension MessageBody {
    static var emptyBuffer: [UInt8] {
        return [UInt8](count: self.length, repeatedValue: 0)
    }
}


public protocol DictionaryRepresentable {
    var dictionaryRepresentation: [String: AnyObject] {
        get
    }
}