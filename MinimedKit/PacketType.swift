//
//  PacketType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/2/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

public enum PacketType: UInt8 {
    case MySentry  = 0xA2
    case Meter     = 0xA5
    case CareLink  = 0xA7
    case Sensor    = 0xA8
}
