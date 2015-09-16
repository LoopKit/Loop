//
//  AlertType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/13/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

public enum AlertType: UInt8 {
    case NoDelivery         = 0x04
    case MaxHourlyBolus     = 0x33
    case HighGlucose        = 0x65
    case LowGlucose         = 0x66
    case MeterBGNow         = 0x68
    case MeterBGSoon        = 0x69
    case CalibrationError   = 0x6a
    case SensorEnd          = 0x6b
    case WeakSignal         = 0x70
    case LostSensor         = 0x71
    case HighPredicted      = 0x72
    case LowPredicted       = 0x73
}