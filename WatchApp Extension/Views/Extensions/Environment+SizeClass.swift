//
//  Environment.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/6/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


extension EnvironmentValues {
    var sizeClass: WKInterfaceDevice.SizeClass {
        get { self[SizeClassKey.self] }
        set { self[SizeClassKey.self] = newValue }
    }
}


private struct SizeClassKey: EnvironmentKey {
    static let defaultValue = WKInterfaceDevice.current().sizeClass
}


extension WKInterfaceDevice {
    enum SizeClass: CaseIterable {
        // Apple Watch Series 3 and earlier
        case size38mm
        case size42mm

        // Apple Watch Series 4 and later
        case size40mm
        case size44mm
    }

    var sizeClass: SizeClass {
        if let sizeClass = SizeClass(screenSize: screenBounds.size) {
            return sizeClass
        } else {
            assertionFailure("Unrecognized Watch size \(screenBounds.size)")
            return .size40mm
        }
    }
}

extension WKInterfaceDevice.SizeClass {
    init?(screenSize: CGSize) {
        let sizeClassesWithSizes = WKInterfaceDevice.SizeClass.allCases.map { (sizeClass: $0, screenSize: $0.screenSize) }
        guard let sizeClass = sizeClassesWithSizes.first(where: { $0.screenSize == screenSize })?.sizeClass else {
            return nil
        }

        self = sizeClass
    }

    var screenSize: CGSize {
        switch self {
        case .size38mm:
            return CGSize(width: 136, height: 170)
        case .size42mm:
            return CGSize(width: 156, height: 195)
        case .size40mm:
            return CGSize(width: 162, height: 197)
        case .size44mm:
            return CGSize(width: 184, height: 224)
        }
    }

    var hasRoundedCorners: Bool {
        self == .size40mm || self == .size44mm
    }
}
