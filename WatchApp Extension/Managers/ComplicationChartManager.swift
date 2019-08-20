//
//  ComplicationChartManager.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 10/17/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit
import HealthKit
import WatchKit

private let textInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

extension CGSize {
    fileprivate static let glucosePoint = CGSize(width: 2, height: 2)
}

extension NSAttributedString {
    fileprivate class func forGlucoseLabel(string: String) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: [
            .font: UIFont(name: "HelveticaNeue", size: 10)!,
            .foregroundColor: UIColor.chartLabel
        ])
    }
}

extension CGFloat {
    fileprivate static let predictionDashPhase: CGFloat = 11
}

private let predictionDashLengths: [CGFloat] = [5, 3]


final class ComplicationChartManager {
    private enum GlucoseLabelPosition {
        case high
        case low
    }

    var data: GlucoseChartData?
    private var lastRenderDate: Date?
    private var renderedChartImage: UIImage?
    private var visibleInterval: TimeInterval = .hours(4)

    private var unit: HKUnit {
        return data?.unit ?? .milligramsPerDeciliter
    }

    func renderChartImage(size: CGSize, scale: CGFloat) -> UIImage? {
        guard let data = data else {
            renderedChartImage = nil
            return nil
        }

        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        drawChart(in: context, data: data, size: size)

        guard let cgImage = context.makeImage() else {
            renderedChartImage = nil
            return nil
        }

        let image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        renderedChartImage = image
        return image
    }

    private func drawChart(in context: CGContext, data: GlucoseChartData, size: CGSize) {
        let now = Date()
        lastRenderDate = now
        let spannedInterval = DateInterval(start: now - visibleInterval / 2, duration: visibleInterval)
        let glucoseRange = data.chartableGlucoseRange(from: spannedInterval)
        let scaler = GlucoseChartScaler(size: size, dateInterval: spannedInterval, glucoseRange: glucoseRange, unit: unit)

        let drawingSteps = [drawTargetRange, drawOverridesIfNeeded, drawHistoricalGlucose, drawPredictedGlucose, drawGlucoseLabels]
        drawingSteps.forEach { drawIn in drawIn(context, scaler) }
    }

    private func drawGlucoseLabels(in context: CGContext, using scaler: GlucoseChartScaler) {
        let formatter = NumberFormatter.glucoseFormatter(for: unit)
        drawGlucoseLabelText(formatter.string(from: scaler.glucoseMax)!, position: .high, scaler: scaler)
        drawGlucoseLabelText(formatter.string(from: scaler.glucoseMin)!, position: .low, scaler: scaler)
    }

    private func drawGlucoseLabelText(_ text: String, position: GlucoseLabelPosition, scaler: GlucoseChartScaler) {
        let attributedText = NSAttributedString.forGlucoseLabel(string: text)
        let size = attributedText.size()
        let x = scaler.xCoordinate(for: scaler.dates.end) - size.width - textInsets.right
        let y: CGFloat = {
            switch position {
            case .high:
                return scaler.yCoordinate(for: scaler.glucoseMax) + textInsets.top
            case .low:
                return scaler.yCoordinate(for: scaler.glucoseMin) - size.height - textInsets.bottom
            }
        }()
        let rect = CGRect(origin: CGPoint(x: x, y: y), size: size).alignedToScreenScale(WKInterfaceDevice.current().screenScale)
        attributedText.draw(with: rect, options: .usesLineFragmentOrigin, context: nil)
    }

    private func drawTargetRange(in context: CGContext, using scaler: GlucoseChartScaler) {
        let activeOverride = data?.activeScheduleOverride
        let targetRangeAlpha: CGFloat = activeOverride != nil ? 0.2 : 0.3
        context.setFillColor(UIColor.glucose.withAlphaComponent(targetRangeAlpha).cgColor)
        data?.correctionRange?.quantityBetween(start: scaler.dates.start, end: scaler.dates.end).forEach { range in
            let rangeRect = scaler.rect(for: range, unit: unit)
            context.fill(rangeRect)
        }
    }

    private func drawOverridesIfNeeded(in context: CGContext, using scaler: GlucoseChartScaler) {
        guard
            let override = data?.activeScheduleOverride,
            let overrideHashable = TemporaryScheduleOverrideHashable(override)
        else {
            return
        }
        context.setFillColor(UIColor.glucose.withAlphaComponent(0.4).cgColor)
        let overrideRect = scaler.rect(for: overrideHashable, unit: unit)
        context.fill(overrideRect)
    }

    private func drawHistoricalGlucose(in context: CGContext, using scaler: GlucoseChartScaler) {
        context.setFillColor(UIColor.glucose.cgColor)
        data?.historicalGlucose?.lazy.filter {
            scaler.dates.contains($0.startDate)
        }.forEach { glucose in
            let origin = scaler.point(for: glucose, unit: unit)
            let glucoseRect = CGRect(origin: origin, size: .glucosePoint).alignedToScreenScale(WKInterfaceDevice.current().screenScale)
            context.fill(glucoseRect)
        }
    }

    private func drawPredictedGlucose(in context: CGContext, using scaler: GlucoseChartScaler) {
        guard let predictedGlucose = data?.predictedGlucose, predictedGlucose.count > 2 else {
            return
        }
        let predictedPath = CGMutablePath()
        let glucosePoints = predictedGlucose.map { scaler.point(for: $0, unit: unit) }
        predictedPath.addLines(between: glucosePoints)
        let dashedPath = predictedPath.copy(dashingWithPhase: .predictionDashPhase, lengths: predictionDashLengths)
        context.setStrokeColor(UIColor.white.cgColor)
        context.addPath(dashedPath)
        context.strokePath()
    }
}
