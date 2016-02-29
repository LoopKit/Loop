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

                let yAxisOverlayView = UIView(frame: CGRect(x: yAxis.rect.origin.x, y: 0, width: yAxis.rect.width, height: chart.frame.height))
                yAxisOverlayView.backgroundColor = UIColor.whiteColor()
                yAxisOverlayView.opaque = true
                containerView.addSubview(yAxisOverlayView)

                let point = ChartPointEllipseView(center: chartPointModel.screenLoc, diameter: 16)
                point.fillColor = tintColor.colorWithAlphaComponent(0.5)

                if let text = chartPointModel.chartPoint.y.labels.first?.text {
                    let label = UILabel()
                    label.font = UIFont.monospacedDigitSystemFontOfSize(12, weight: UIFontWeightBold)

                    label.text = text
                    label.textColor = tintColor
                    label.sizeToFit()
                    label.center.y = chartPointModel.screenLoc.y
                    label.frame.origin.x = yAxisOverlayView.frame.width - label.frame.width - 2
                    
                    containerView.addSubview(label)
                }

                if let text = chartPointModel.chartPoint.x.labels.first?.text {
                    let label = UILabel()
                    label.font = UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1)
                    label.text = text
                    label.textColor = UIColor.secondaryLabelColor
                    label.sizeToFit()
                    label.center = CGPoint(x: chartPointModel.screenLoc.x, y: xAxisOverlayView.center.y)

                    containerView.addSubview(label)
                }

                containerView.addSubview(point)
                
                return containerView
            }
        )

    }
}
