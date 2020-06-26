//
//  CGMStatusHUDViewModel.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-24.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit

public class CGMStatusHUDViewModel {
    
    static let staleGlucoseRepresentation: String = "---"
    
    var trend: GlucoseTrend? = nil
    
    var unitsString: String = "–"
    
    var glucoseValueString: String = CGMStatusHUDViewModel.staleGlucoseRepresentation
    
    var accessibilityString: String = ""
    
    var tintColor: UIColor?
    
    var staleGlucoseValueHandler: (String) -> Void
    
    var isVisible: Bool = true {
        didSet {
            if oldValue != isVisible {
                if !isVisible {
                    stalenessTimer?.invalidate()
                    stalenessTimer = nil
                } else {
                    startStalenessTimerIfNeeded()
                }
            }
        }
    }
    
    private var stalenessTimer: Timer?
    
    private var isStaleAt: Date? {
        didSet {
            if oldValue != isStaleAt {
                stalenessTimer?.invalidate()
                stalenessTimer = nil
            }
        }
    }
    
    private func startStalenessTimerIfNeeded() {
        if let fireDate = isStaleAt,
            isVisible,
            stalenessTimer == nil
        {
            stalenessTimer = Timer(fire: fireDate, interval: 0, repeats: false) { (_) in
                self.staleGlucoseValueHandler(CGMStatusHUDViewModel.staleGlucoseRepresentation)
            }
            RunLoop.main.add(stalenessTimer!, forMode: .default)
        }
    }
    
    private lazy var timeFormatter = DateFormatter(timeStyle: .short)
    
    init(staleGlucoseValueHandler: @escaping (String) -> Void) {
        self.staleGlucoseValueHandler = staleGlucoseValueHandler
    }
    
    func setGlucoseQuantity(_ glucoseQuantity: Double,
                            at glucoseStartDate: Date,
                            unit: HKUnit,
                            staleGlucoseAge: TimeInterval,
                            sensor: SensorDisplayable?)
    {
        var accessibilityStrings = [String]()
        
        let time = timeFormatter.string(from: glucoseStartDate)
        
        isStaleAt = glucoseStartDate.addingTimeInterval(staleGlucoseAge)
        let glucoseValueCurrent = Date() < isStaleAt!
        
        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        if let valueString = numberFormatter.string(from: glucoseQuantity) {
            if glucoseValueCurrent {
                glucoseValueString = valueString
                startStalenessTimerIfNeeded()
            } else {
                glucoseValueString = CGMStatusHUDViewModel.staleGlucoseRepresentation
            }
            accessibilityStrings.append(String(format: LocalizedString("%1$@ at %2$@", comment: "Accessbility format value describing glucose: (1: glucose number)(2: glucose time)"), valueString, time))
        }
        
        if let trend = sensor?.trendType, glucoseValueCurrent {
            self.trend = trend
            accessibilityStrings.append(trend.localizedDescription)
        } else {
            trend = nil
        }
        
        tintColor = sensor?.glucoseValueType?.color
        
        unitsString = unit.localizedShortUnitString
        accessibilityString = accessibilityStrings.joined(separator: ", ")
    }
}
