//
//  ChartValues.swift
//  Loop Widget Extension
//
//  Created by Bastiaan Verhaar on 25/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation

struct ChartValues: Identifiable {
    public let id: UUID
    public let x: Date
    public let y: Double
    
    init(x: Date, y: Double) {
        self.id = UUID()
        self.x = x
        self.y = y
    }
    
    static func convert(data: [Double], startDate: Date, interval: TimeInterval) -> [ChartValues] {
        let twoHours = Date.now.addingTimeInterval(.hours(2))
        
        return data.enumerated().filter { (index, item) in
            return startDate.addingTimeInterval(interval * Double(index)) < twoHours
        }.map { (index, item) in
            return ChartValues(
                x: startDate.addingTimeInterval(interval * Double(index)),
                y: item
            )
        }
    }
    
    static func convert(data: [GlucoseSampleAttributes]) -> [ChartValues] {
        return data.map { item in
            return ChartValues(
                x: item.x,
                y: item.y
            )
        }
    }
}
