//
//  ChartValues.swift
//  Loop Widget Extension
//
//  Created by Bastiaan Verhaar on 25/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import Charts

struct ChartView: View {
    private let glucoseSampleData: [ChartValues]
    private let predicatedData: [ChartValues]
    
    init(glucoseSamples: [GlucoseSampleAttributes], predicatedGlucose: [Double], predicatedStartDate: Date?, predicatedInterval: TimeInterval?, lowerLimit: Double, upperLimit: Double) {
        self.glucoseSampleData = ChartValues.convert(data: glucoseSamples, lowerLimit: lowerLimit, upperLimit: upperLimit)
        self.predicatedData = ChartValues.convert(
            data: predicatedGlucose,
            startDate: predicatedStartDate ?? Date.now,
            interval: predicatedInterval ?? .minutes(5),
            lowerLimit: lowerLimit,
            upperLimit: upperLimit
        )
    }
    
    init(glucoseSamples: [GlucoseSampleAttributes], lowerLimit: Double, upperLimit: Double) {
        self.glucoseSampleData = ChartValues.convert(data: glucoseSamples, lowerLimit: lowerLimit, upperLimit: upperLimit)
        self.predicatedData = []
    }
    
    var body: some View {
        Chart {
            ForEach(glucoseSampleData) { item in
                PointMark (x: .value("Date", item.x),
                          y: .value("Glucose level", item.y)
                )
                .symbolSize(20)
                .foregroundStyle(by: .value("Color", item.color))
            }
            
            ForEach(predicatedData) { item in
                LineMark (x: .value("Date", item.x),
                          y: .value("Glucose level", item.y)
                )
                .lineStyle(StrokeStyle(lineWidth: 3, dash: [2, 3]))
            }
        }
            .chartForegroundStyleScale([
                "Good": .green,
                "High": .orange,
                "Low": .red
            ])
            .chartPlotStyle { plotContent in
                plotContent.background(.cyan.opacity(0.15))
            }
            .chartLegend(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisValueLabel().foregroundStyle(Color.primary)
                    AxisGridLine(stroke: .init(lineWidth: 0.1, dash: [2, 3]))
                        .foregroundStyle(Color.primary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .automatic, values: .stride(by: .hour)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .narrow)).minute(.twoDigits), anchor: .top)
                        .foregroundStyle(Color.primary)
                    AxisGridLine(stroke: .init(lineWidth: 0.1, dash: [2, 3]))
                        .foregroundStyle(Color.primary)
                }
            }
    }
}

struct ChartValues: Identifiable {
    public let id: UUID
    public let x: Date
    public let y: Double
    public let color: String
    
    init(x: Date, y: Double, color: String) {
        self.id = UUID()
        self.x = x
        self.y = y
        self.color = color
    }
    
    static func convert(data: [Double], startDate: Date, interval: TimeInterval, lowerLimit: Double, upperLimit: Double) -> [ChartValues] {
        let twoHours = Date.now.addingTimeInterval(.hours(4))
        
        return data.enumerated().filter { (index, item) in
            return startDate.addingTimeInterval(interval * Double(index)) < twoHours
        }.map { (index, item) in
            return ChartValues(
                x: startDate.addingTimeInterval(interval * Double(index)),
                y: item,
                color: item < lowerLimit ? "Low" : item > upperLimit ? "High" : "Good"
            )
        }
    }
    
    static func convert(data: [GlucoseSampleAttributes], lowerLimit: Double, upperLimit: Double) -> [ChartValues] {
        return data.map { item in
            return ChartValues(
                x: item.x,
                y: item.y,
                color: item.y < lowerLimit ? "Low" : item.y > upperLimit ? "High" : "Good"
            )
        }
    }
}
