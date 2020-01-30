//
//  GlucoseChartScaler.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 10/17/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreGraphics
import HealthKit
import LoopKit
import WatchKit


enum CoordinateSystem {
    /// The graphics coordinate system in which the origin is the top left corner.
    /// Use in working with UIKit and CoreGraphics.
    case standard

    /// The graphics coordinate system in which the origin is the bottom left corner.
    /// Use in working with SpriteKit.
    case inverted
}

struct GlucoseChartScaler {
    let dates: DateInterval
    let glucoseMin: Double
    let glucoseMax: Double
    let xScale: CGFloat
    let yScale: CGFloat
    let coordinateSystem: CoordinateSystem

    func xCoordinate(for date: Date) -> CGFloat {
        return CGFloat(date.timeIntervalSince(dates.start)) * xScale
    }

    func yCoordinate(for glucose: Double) -> CGFloat {
        switch coordinateSystem {
        case .standard:
            return CGFloat(glucoseMax - glucose) * yScale
        case .inverted:
            return CGFloat(glucose - glucoseMin) * yScale
        }
    }

    func point(_ date: Date, _ glucose: Double) -> CGPoint {
        return CGPoint(x: xCoordinate(for: date), y: yCoordinate(for: glucose))
    }

    func point(for glucose: SampleValue, unit: HKUnit) -> CGPoint {
        return point(glucose.startDate, glucose.quantity.doubleValue(for: unit))
    }

    // By default enforce a minimum height so that the range is visible
    func rect(
        for range: GlucoseChartValueHashable,
        unit: HKUnit,
        minHeight: CGFloat = 2,
        alignedToScreenScale screenScale: CGFloat = WKInterfaceDevice.current().screenScale
    ) -> CGRect {

        let minY = range.min.doubleValue(for: unit)
        let maxY = range.max.doubleValue(for: unit)

        switch coordinateSystem {
        case .standard:
            let topLeft = point(max(dates.start, range.start), maxY)
            let bottomRight = point(min(dates.end, range.end), minY)
            let size = CGSize(width: bottomRight.x - topLeft.x, height: max(bottomRight.y - topLeft.y, minHeight))
            return CGRect(origin: topLeft, size: size).alignedToScreenScale(screenScale)
        case .inverted:
            let bottomLeft = point(max(dates.start, range.start), minY)
            let topRight = point(min(dates.end, range.end), maxY)
            let size = CGSize(width: topRight.x - bottomLeft.x, height: max(topRight.y - bottomLeft.y, minHeight))
            return CGRect(origin: bottomLeft, size: size).alignedToScreenScale(screenScale)
        }
    }
}

extension GlucoseChartScaler {
    init(size: CGSize, dateInterval: DateInterval, glucoseRange: ClosedRange<HKQuantity>, unit: HKUnit, coordinateSystem: CoordinateSystem = .standard) {
        self.dates = dateInterval
        self.glucoseMin = glucoseRange.lowerBound.doubleValue(for: unit)
        self.glucoseMax = glucoseRange.upperBound.doubleValue(for: unit)
        self.xScale = size.width / CGFloat(dateInterval.duration)
        self.yScale = size.height / CGFloat(glucoseRange.span(with: unit))
        self.coordinateSystem = coordinateSystem
    }
}

extension ClosedRange where Bound == HKQuantity {
    fileprivate func span(with unit: HKUnit) -> Double {
        return upperBound.doubleValue(for: unit) - lowerBound.doubleValue(for: unit)
    }
}
