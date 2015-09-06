//
//  MessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/4/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public protocol MessageBody {
    init?(rxData: NSData)

    var txData: NSData {
        get
    }
}