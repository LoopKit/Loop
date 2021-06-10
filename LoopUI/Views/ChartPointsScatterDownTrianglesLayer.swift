//
//  ChartPointsScatterDownTrianglesLayer.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import SwiftCharts


public class ChartPointsScatterDownTrianglesLayer<T: ChartPoint>: ChartPointsScatterLayer<T> {
    public required init(
        xAxis: ChartAxis,
        yAxis: ChartAxis,
        chartPoints: [T],
        displayDelay: Float,
        itemSize: CGSize,
        itemFillColor: UIColor,
        optimized: Bool = false,
        tapSettings: ChartPointsTapSettings<T>? = nil
    ) {
        // optimized must be set to false because `generateCGLayer` isn't public and can't be overridden
        super.init(
            xAxis: xAxis,
            yAxis: yAxis,
            chartPoints: chartPoints,
            displayDelay: displayDelay,
            itemSize: itemSize,
            itemFillColor: itemFillColor,
            optimized: false,
            tapSettings: tapSettings
        )
    }

    public override func drawChartPointModel(_ context: CGContext, chartPointModel: ChartPointLayerModel<T>, view: UIView) {
        let w = self.itemSize.width
        let h = self.itemSize.height

        let horizontalOffset = -view.frame.origin.x
        let verticalOffset = -view.frame.origin.y

        let path = CGMutablePath()
        path.move(to: CGPoint(x: chartPointModel.screenLoc.x + horizontalOffset, y: chartPointModel.screenLoc.y + verticalOffset + h / 2))
        path.addLine(to: CGPoint(x: chartPointModel.screenLoc.x + horizontalOffset + w / 2, y: chartPointModel.screenLoc.y + verticalOffset - h / 2))
        path.addLine(to: CGPoint(x: chartPointModel.screenLoc.x + horizontalOffset - w / 2, y: chartPointModel.screenLoc.y + verticalOffset - h / 2))
        path.closeSubpath()

        context.setFillColor(self.itemFillColor.cgColor)
        context.addPath(path)
        context.fillPath()
    }
}
