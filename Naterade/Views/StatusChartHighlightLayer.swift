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
                let overlayView = U(frame: chart.frame)

                let point = ChartPointEllipseView(center: chartPointModel.screenLoc, diameter: 16)
                point.fillColor = tintColor.colorWithAlphaComponent(0.5)

                if let text = chartPointModel.chartPoint.y.labels.first?.text {
                    let label = UILabel()
                    label.font = UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1)
                    label.text = text
                    label.textColor = tintColor
                    label.backgroundColor = UIColor.whiteColor()
                    label.opaque = true
                    label.sizeToFit()
                    label.center = CGPoint(x: chartPointModel.screenLoc.x, y: labelCenterY)
                    
                    overlayView.addSubview(label)
                }

                overlayView.addSubview(point)
                
                return overlayView
            }
        )

    }
}
