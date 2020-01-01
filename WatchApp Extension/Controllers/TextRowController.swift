//
//  TextRowController.swift
//  WatchApp Extension
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopCore
import WatchKit

class TextRowController: NSObject, IdentifiableClass {
    @IBOutlet private(set) var textLabel: WKInterfaceLabel!
    @IBOutlet private(set) var detailTextLabel: WKInterfaceLabel!
}
