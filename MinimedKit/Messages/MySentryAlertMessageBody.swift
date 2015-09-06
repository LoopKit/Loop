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
a2 594040 01 7c 650727070f09060175 4c
```
*/
public struct MySentryAlertMessageBody: MessageBody {
    public static let length = 10

    public init?(rxData: NSData) {
        if rxData.length == self.dynamicType.length {

        } else {
            return nil
        }
    }

    public var txData: NSData {
        return NSData()
    }
}