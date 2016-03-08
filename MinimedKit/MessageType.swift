//
//  MessageType.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/2/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

public enum MessageType: UInt8 {
    case Alert          = 0x01
    case AlertCleared   = 0x02
    case DeviceTest     = 0x03
    case PumpStatus     = 0x04
    case PumpStatusAck  = 0x06
    case PumpBackfill   = 0x08
    case FindDevice     = 0x09
    case DeviceLink     = 0x0A
    case Bolus          = 0x42
    case SetTempBasal   = 0x4c
    case PowerOn        = 0x5d
    case GetBattery     = 0x72
    case GetPumpModel   = 0x8d
    case ReadTempBasal  = 0x98
    case ReadSettings   = 0xc0

    var bodyType: MessageBody.Type {
        switch self {
        case .Alert:
            return MySentryAlertMessageBody.self
        case .AlertCleared:
            return MySentryAlertClearedMessageBody.self
        case .PumpStatus:
            return MySentryPumpStatusMessageBody.self
        case .PumpStatusAck:
            return MySentryAckMessageBody.self
        case .ReadTempBasal:
            return ReadTempBasalCarelinkMessageBody.self
        case .ReadSettings:
            return ReadSettingsCarelinkMessageBody.self
        default:
            return UnknownMessageBody.self
        }
    }
}
