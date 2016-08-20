//
//  StatusChartHighlightLayer.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import SwiftCharts


final class ChartPointsTouchHighlightLayerViewCache {
    private lazy var containerView = UIView(frame: .zero)

    private lazy var xAxisOverlayView = UIView()

    private lazy var point = ChartPointEllipseView(center: .zero, diameter: 16)

    private lazy var labelY: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFontOfSize(15, weight: UIFontWeightBold)
        label.textAlignment = .Center
        label.backgroundColor = UIColor.whiteColor()

        return label
    }()

    private lazy var labelX: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1)
        label.textColor = UIColor.secondaryLabelColor

        return label
    }()

    private(set) var highlightLayer: ChartPointsTouchHighlightLayer<ChartPoint, UIView>!

    init(xAxis: ChartAxisLayer, yAxis: ChartAxisLayer, innerFrame: CGRect, chartPoints: [ChartPoint], tintColor: UIColor, labelCenterY: CGFloat, gestureRecognizer: UIPanGestureRecognizer? = nil) {

        highlightLayer = ChartPointsTouchHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: chartPoints,
            gestureRecognizer: gestureRecognizer,
            modelFilter: { (screenLoc, chartPointModels) -> ChartPointLayerModel<ChartPoint>? in
                if let index = chartPointModels.map({ $0.screenLoc.x }).findClosestElementIndexToValue(screenLoc.x) {
                    return chartPointModels[index]
                } else {
                    return nil
                }
            },
            viewGenerator: { [unowned self] (chartPointModel, layer, chart) -> UIView? in
                let containerView = self.containerView
                containerView.frame = chart.bounds
                containerView.alpha = 1  // This is animated to 0 when touch last ended

                let xAxisOverlayView = self.xAxisOverlayView
                if xAxisOverlayView.superview == nil {
                    xAxisOverlayView.frame = xAxis.rect.offsetBy(dx: 0, dy: 1)
                    xAxisOverlayView.backgroundColor = UIColor.whiteColor()
                    xAxisOverlayView.opaque = true
                    containerView.addSubview(xAxisOverlayView)
                }

                let point = self.point
                point.center = chartPointModel.screenLoc
                if point.superview == nil {
                    point.fillColor = tintColor.colorWithAlphaComponent(0.5)
                    containerView.addSubview(point)
                }

                if let text = chartPointModel.chartPoint.y.labels.first?.text {
                    let label = self.labelY

                    label.text = text
                    label.sizeToFit()
                    label.frame.size.height += 4
                    label.frame.size.width += label.frame.size.height / 2
                    label.center.y = innerFrame.origin.y - 1
                    label.center.x = chartPointModel.screenLoc.x
                    label.frame.origin.x = min(max(label.frame.origin.x, innerFrame.origin.x), innerFrame.maxX - label.frame.size.width)
                    label.frame.origin.makeIntegralInPlaceWithDisplayScale(chart.view.traitCollection.displayScale)
                    label.layer.cornerRadius = label.frame.size.height / 2
                    label.layer.borderWidth = 1 / max(1, chart.view.traitCollection.displayScale)

                    if label.superview == nil {
                        label.textColor = tintColor
                        label.layer.borderColor = tintColor.CGColor

                        containerView.addSubview(label)
                    }
                }

                if let text = chartPointModel.chartPoint.x.labels.first?.text {
                    let label = self.labelX
                    label.text = text
                    label.sizeToFit()
                    label.center = CGPoint(x: chartPointModel.screenLoc.x, y: xAxisOverlayView.center.y)
                    label.frame.origin.makeIntegralInPlaceWithDisplayScale(chart.view.traitCollection.displayScale)

                    if label.superview == nil {
                        containerView.addSubview(label)
                    }
                }
                
                return containerView
            }
        )
    }
}
