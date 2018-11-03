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


private enum ComplicationChartConstants {
    static let textInsets = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
    static let glucoseSize = CGSize(width: 1, height: 1)
    static let glucoseLabelAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont(name: "HelveticaNeue", size: 5)!,
        .foregroundColor: UIColor.chartLabel
    ]
}

private enum GlucoseLabelPosition {
    case high
    case low
}

final class ComplicationChartManager {
    var data: GlucoseChartData?
    var lastRenderDate: Date?
    var renderedChartImage: UIImage?
    var visibleInterval: TimeInterval = .hours(4)

    private var unit: HKUnit {
        return data?.unit ?? .milligramsPerDeciliter
    }

    func renderChartImage(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        let context = UIGraphicsGetCurrentContext()!
        drawChart(in: context, size: size)
        let image = context.makeImage().map(UIImage.init(cgImage:))
        renderedChartImage = image
        return image
    }

    private func drawChart(in context: CGContext, size: CGSize) {
        guard let data = data else {
            // TODO: handle empty data case
            return
        }

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
        let attributedText = NSAttributedString(string: text, attributes: ComplicationChartConstants.glucoseLabelAttributes)
        let size = attributedText.size()
        let x = scaler.xCoordinate(for: scaler.dates.end) - size.width -  ComplicationChartConstants.textInsets.right
        let y: CGFloat = {
            switch position {
            case .high:
                return scaler.yCoordinate(for: scaler.glucoseMax) + ComplicationChartConstants.textInsets.top
            case .low:
                return scaler.yCoordinate(for: scaler.glucoseMin) - size.height - ComplicationChartConstants.textInsets.bottom
            }
        }()
        let rect = CGRect(origin: CGPoint(x: x, y: y), size: size).alignedToScreenScale(WKInterfaceDevice.current().screenScale)
        attributedText.draw(with: rect, options: .usesLineFragmentOrigin, context: nil)
    }

    private func drawTargetRange(in context: CGContext, using scaler: GlucoseChartScaler) {
        let activeOverride = data?.correctionRange?.activeOverride
        let targetRangeAlpha: CGFloat = activeOverride != nil ? 0.2 : 0.3
        context.setFillColor(UIColor.glucose.withAlphaComponent(targetRangeAlpha).cgColor)
        data?.correctionRange?.quantityBetween(start: scaler.dates.start, end: scaler.dates.end).forEach { range in
            let rangeRect = scaler.rect(for: range, unit: unit)
            context.fill(rangeRect)
        }
    }

    private func drawOverridesIfNeeded(in context: CGContext, using scaler: GlucoseChartScaler) {
        guard let override = data?.correctionRange?.activeOverride else {
            return
        }
        context.setFillColor(UIColor.glucose.withAlphaComponent(0.4).cgColor)
        let overrideRect = scaler.rect(for: override, unit: unit)
        context.fill(overrideRect)
    }

    private func drawHistoricalGlucose(in context: CGContext, using scaler: GlucoseChartScaler) {
        context.setFillColor(UIColor.glucose.cgColor)
        data?.historicalGlucose?.lazy
            .filter { scaler.dates.contains($0.startDate) }
            .forEach { glucose in
                let origin = scaler.point(for: glucose, unit: unit)
                let glucoseRect = CGRect(origin: origin, size: ComplicationChartConstants.glucoseSize).alignedToScreenScale(WKInterfaceDevice.current().screenScale)
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
        let dashedPath = predictedPath.copy(dashingWithPhase: 6.5, lengths: [2.5, 1.5])
        context.setStrokeColor(UIColor.white.cgColor)
        context.addPath(dashedPath)
        context.strokePath()
    }
}
