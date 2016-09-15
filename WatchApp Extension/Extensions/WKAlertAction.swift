//
//  WKAlertAction.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import WatchKit


extension WKAlertAction {
    static func dismissAction() -> Self {
        return self.init(
            title: NSLocalizedString("Dismiss", comment: "The action button title to dismiss an error message"),
            style: .cancel,
            handler: { }
        )
    }
}
