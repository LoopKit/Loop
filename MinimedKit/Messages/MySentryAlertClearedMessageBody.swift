//
//  MySentryAlertClearedMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


/**
Describes message sent immediately from the pump to any paired MySentry devices after a user clears an alert

See: [MinimedRF Class](https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/alert_cleared.rb)

```
a2 594040 02 80 52 14
```
*/
public struct MySentryAlertClearedMessageBody: MessageBody, DictionaryRepresentable {
    public static let length = 2

    public let alertType: AlertType?

    private let rxData: NSData

    public init?(rxData: NSData) {
        if rxData.length == self.dynamicType.length {
            self.rxData = rxData

            alertType = AlertType(rawValue: rxData[1])
        } else {
            return nil
        }
    }

    public var txData: NSData {
        return NSData()
    }

    public var dictionaryRepresentation: [String: AnyObject] {
        return [
            "alertType": alertType != nil ? String(alertType!) : rxData.subdataWithRange(NSRange(1...1)).hexadecimalString,
            "cleared": true
        ]
    }
}