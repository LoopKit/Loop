//
//  StatusChartHighlightLayer.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import SwiftCharts


class StatusChartHighlightLayer<T: ChartPoint, U: UIView>: ChartPointsTouchHighlightLayer<T, U> {
    init(
        xAxis: ChartAxisLayer,
        yAxis: ChartAxisLayer,
        innerFrame: CGRect,
        chartPoints: [T],
        tintColor: UIColor,
        labelCenterY: CGFloat = 0,
        gestureRecognizer: UIPanGestureRecognizer? = nil
    ) {
        super.init(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: chartPoints, gestureRecognizer: gestureRecognizer,
            modelFilter: { (screenLoc, chartPointModels) -> ChartPointLayerModel<T>? in
                if let index = chartPointModels.map({ $0.screenLoc.x }).findClosestElementIndexToValue(screenLoc.x) {
                    return chartPointModels[index]
                } else {
                    return nil
                }
            },
            viewGenerator: { (chartPointModel, layer, chart) -> U? in
                let containerView = U(frame: chart.frame)

                let xAxisOverlayView = UIView(frame: xAxis.rect.offsetBy(dx: 0, dy: 1))
                xAxisOverlayView.backgroundColor = UIColor.whiteColor()
                xAxisOverlayView.opaque = true
                containerView.addSubview(xAxisOverlayView)

                let point = ChartPointEllipseView(center: chartPointModel.screenLoc, diameter: 16)
                point.fillColor = tintColor.colorWithAlphaComponent(0.5)
                containerView.addSubview(point)

                if let text = chartPointModel.chartPoint.y.labels.first?.text {
                    let label = UILabel()
                    label.font = UIFont.monospacedDigitSystemFontOfSize(15, weight: UIFontWeightBold)

                    label.text = text
                    label.textColor = tintColor
                    label.textAlignment = .Center
                    label.sizeToFit()
                    label.frame.size.height += 4
                    label.frame.size.width += label.frame.size.height / 2
                    label.center.y = innerFrame.origin.y - 1
                    label.center.x = chartPointModel.screenLoc.x
                    label.frame.origin.x = min(max(label.frame.origin.x, innerFrame.origin.x), innerFrame.maxX - label.frame.size.width)
                    label.frame.origin.makeIntegralInPlaceWithDisplayScale(chart.view.traitCollection.displayScale)
                    label.layer.borderColor = tintColor.CGColor
                    label.layer.borderWidth = 1 / chart.view.traitCollection.displayScale
                    label.layer.cornerRadius = label.frame.size.height / 2
                    label.backgroundColor = UIColor.whiteColor()

                    containerView.addSubview(label)
                }

                if let text = chartPointModel.chartPoint.x.labels.first?.text {
                    let label = UILabel()
                    label.font = UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1)
                    label.text = text
                    label.textColor = UIColor.secondaryLabelColor
                    label.sizeToFit()
                    label.center = CGPoint(x: chartPointModel.screenLoc.x, y: xAxisOverlayView.center.y)
                    label.frame.origin.makeIntegralInPlaceWithDisplayScale(chart.view.traitCollection.displayScale)

                    containerView.addSubview(label)
                }
                
                return containerView
            }
        )

    }
}
