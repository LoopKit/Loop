//
//  AlertType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/13/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

public enum AlertType: UInt8 {
    case NoDelivery     = 0x04
    case MaxHourlyBolus = 0x33
    case HighPredicted  = 0x72
    case LowPredicted   = 0x73
    case MeterBGNow     = 0x68
}