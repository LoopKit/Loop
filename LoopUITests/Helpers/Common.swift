//
//  Common.swift
//  LoopUITests
//
//  Created by Ginny Yadav on 10/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import XCTest

@MainActor
class Common {
    struct TestSettings {
        static let elementTimeout: TimeInterval = 5
    }
}

func waitForExistence(_ element: XCUIElement) {
    XCTAssert(element.waitForExistence(timeout: Common.TestSettings.elementTimeout))
}

extension XCUIElement {
    func forceTap() {
        if self.isHittable {
            self.tap()
        }
        else {
            let coordinate: XCUICoordinate = self.coordinate(withNormalizedOffset: CGVector(dx:0.0, dy:0.0))
            coordinate.tap()
        }
    }
}
