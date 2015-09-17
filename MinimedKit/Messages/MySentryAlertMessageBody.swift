//
//  MySentryAlertMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


/**
Describes an alert message sent immediately from the pump to any paired MySentry devices

See: [MinimedRF Class](https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/alert.rb)

```
a2 594040 01 7c 65 0727070f0906 0175 4c
```
*/
public struct MySentryAlertMessageBody: MessageBody, DictionaryRepresentable {
    public static let length = 10

    public let alertType: AlertType?
    public let alertDate: NSDate

    private let rxData: NSData

    public init?(rxData: NSData) {
        if rxData.length == self.dynamicType.length, let
            alertDate = NSDateComponents(mySentryBytes: rxData[2...7]).date
        {
            self.rxData = rxData

            alertType = AlertType(rawValue: rxData[1])
            self.alertDate = alertDate
        } else {
            return nil
        }
    }

    public var txData: NSData {
        return rxData
    }

    public var dictionaryRepresentation: [String: AnyObject] {
        let dateFormatter = NSDateFormatter()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")

        return [
            "alertDate": dateFormatter.stringFromDate(alertDate),
            "alertType": alertType != nil ? String(alertType!) : rxData.subdataWithRange(NSRange(1...1)).hexadecimalString,
            "byte89": rxData.subdataWithRange(NSRange(8...9)).hexadecimalString
        ]

    }
}