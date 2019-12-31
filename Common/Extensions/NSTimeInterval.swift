//
//  NSTimeInterval.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/9/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension TimeInterval {
    static func seconds(_ seconds: Double) -> TimeInterval {
        return seconds
    }

    static func minutes(_ minutes: Double) -> TimeInterval {
        return TimeInterval(minutes: minutes)
    }

    static func hours(_ hours: Double) -> TimeInterval {
        return TimeInterval(hours: hours)
    }

    init(minutes: Double) {
        self.init(minutes * 60)
    }

    init(hours: Double) {
        self.init(minutes: hours * 60)
    }

    var minutes: Double {
        return self / 60.0
    }

    var hours: Double {
        return minutes / 60.0
    }

}
