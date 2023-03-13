//
//  CurrentTimeChartPointsViewsLayer.swift
//  LoopUI
//
//  Created by Chris Almond on 3/12/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftCharts

class VerticalTimeChartLine {
    static var defaultRed: CGColor = .init(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5)
    
    static func create(xAxis: ChartAxis, yAxis: ChartAxis, date: Date = Date.now, color: CGColor = defaultRed) -> ChartPointsViewsLayer<ChartPoint, UIView> {
        let currentTimeChartPoint = ChartPoint(x: ChartAxisValueDouble(date.timeIntervalSince1970), y: ChartAxisValueDouble(0))

        return ChartPointsViewsLayer(xAxis: xAxis, yAxis: yAxis, chartPoints: [currentTimeChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 1
            let viewFrame = CGRect(x: chartPointModel.screenLoc.x, y: 0, width: width, height: chart.contentView.bounds.size.height)
            let view = UIView(frame: viewFrame)
            view.layer.backgroundColor = color
            return view
        })
    }
}
