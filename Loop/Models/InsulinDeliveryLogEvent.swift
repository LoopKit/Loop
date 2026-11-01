//
//  InsulinDeliveryLogEvent.swift
//  Loop
//
//  Created by Cameron Ingham on 3/26/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

struct InsulinDeliveryLogEvent: Hashable, Identifiable {
    enum EventType: Hashable {
        enum PumpEventType: Hashable {
            enum BasalEventType: Hashable {
                enum AutomatedBasalStatus: Hashable {
                    case scheduled
                    case moreThanScheduled
                    case lessThanScheduled
                }
                
                case automationOn(basalStatus: AutomatedBasalStatus)
                case automationOff
                case automatedPresetBasal
                case manualTempBasal(endDate: Date)
            }
            
            case basal(BasalEventType, rate: LoopQuantity)
            
            enum BolusEventType: Hashable {
                case automated
                case meal(recommendedAmount: LoopQuantity, carbAmount: LoopQuantity, emoji: String)
                case correction(recommendedAmount: LoopQuantity?)
                case external
            }
            
            case bolus(BolusEventType, programmedAmount: LoopQuantity?, deliveryAmount: LoopQuantity)
            
            enum InsulinEventType: Hashable {
                case suspended
                case resumed
            }
            
            case insulin(InsulinEventType)
        }
        
        case pumpEvent(PumpEventType, DoseEntry?)
        
        enum AutomationEventType: Hashable {
            case on
            case off(endDate: Date?)
            case unavailable
        }
        
        case automation(AutomationEventType)
        
        enum PresetEventType: Hashable {
            case enabled
            case disabled
        }
        
        case preset(PresetEventType, icon: PresetSymbol?, name: String)
    }
    
    let id: String
    let type: EventType
    let date: Date
}

extension InsulinDeliveryLogEvent {
    var endDate: Date? {
        if case let .automation(.off(endDate)) = type {
            return endDate
        } else if case let .pumpEvent(.basal(.manualTempBasal(endDate), _), _) = type {
            return endDate
        } else {
            return nil
        }
    }
}

extension Array<InsulinDeliveryLogEvent> {
    
    struct LogSegment {
        let start: Date
        let end: Date
        var events: [InsulinDeliveryLogEvent]
    }
    
    func sortedByDate() -> [InsulinDeliveryLogEvent] {
        sorted {
            var isComparingSuspend = false
            if case .pumpEvent(.insulin(.suspended), _) = $0.type {
                isComparingSuspend = true
            }
            
            if $0.date == $1.date, case .pumpEvent(.insulin(.resumed), _) = $1.type, !isComparingSuspend {
                return true
            } else {
                return $0.date > $1.date
            }
        }
    }
    
    func segmentItemsByHour() -> [LogSegment] {
        let calendar = Calendar.current
        
        var itemsByHourRange = [LogSegment]()
        
        for item in sortedByDate() {
            let components = calendar.dateComponents([.day, .hour], from: item.endDate ?? item.date)
            
            guard let hourStart = calendar.date(from: components), let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else {
                continue
            }
            
            let hourRange = hourStart..<hourEnd
            
            if let hourItemsIndex = itemsByHourRange.firstIndex(where: { hourRange.contains($0.start) }) {
                itemsByHourRange[hourItemsIndex].events.append(item)
            } else {
                itemsByHourRange.append(
                    LogSegment(
                        start: hourStart,
                        end: hourEnd,
                        events: [item]
                    )
                )
            }
        }
        
        return itemsByHourRange
    }
}
