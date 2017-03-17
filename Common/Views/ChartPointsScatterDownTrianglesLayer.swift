//
//  ChartPointsScatterDownTrianglesLayer.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import SwiftCharts


class ChartPointsScatterDownTrianglesLayer<T: ChartPoint>: ChartPointsScatterLayer<T> {

    required init(xAxis: ChartAxisLayer, yAxis: ChartAxisLayer, innerFrame: CGRect, chartPoints: [T], displayDelay: Float, itemSize: CGSize, itemFillColor: UIColor) {
        super.init(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: chartPoints, displayDelay: displayDelay, itemSize: itemSize, itemFillColor: itemFillColor)
    }

    override func drawChartPointModel(context: CGContext, chartPointModel: ChartPointLayerModel<T>) {
        let w = self.itemSize.width
        let h = self.itemSize.height

        let path = CGMutablePath()
        path.move(to: CGPoint(x: chartPointModel.screenLoc.x, y: chartPointModel.screenLoc.y + h / 2))
        path.addLine(to: CGPoint(x: chartPointModel.screenLoc.x + w / 2, y: chartPointModel.screenLoc.y - h / 2))
        path.addLine(to: CGPoint(x: chartPointModel.screenLoc.x - w / 2, y: chartPointModel.screenLoc.y - h / 2))
        path.closeSubpath()

        context.setFillColor(self.itemFillColor.cgColor)
        context.addPath(path)
        context.fillPath()
    }
}
