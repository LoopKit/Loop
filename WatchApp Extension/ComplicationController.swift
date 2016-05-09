//
//  ComplicationController.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit


class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Timeline Configuration
    
    func getSupportedTimeTravelDirectionsForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.Backward])
    }
    
    func getTimelineStartDateForComplication(complication: CLKComplication, withHandler handler: (NSDate?) -> Void) {
        if let date = DeviceDataManager.sharedManager.lastContextData?.glucoseDate {
            handler(date)
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEndDateForComplication(complication: CLKComplication, withHandler handler: (NSDate?) -> Void) {
        if let date = DeviceDataManager.sharedManager.lastContextData?.glucoseDate {
            handler(date)
        } else {
            handler(nil)
        }
    }
    
    func getPrivacyBehaviorForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.HideOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntryForComplication(complication: CLKComplication, withHandler handler: ((CLKComplicationTimelineEntry?) -> Void)) {

        switch complication.family {
        case .ModularSmall:
            if let context = DeviceDataManager.sharedManager.lastContextData,
                date = context.glucoseDate where date.timeIntervalSinceNow >= -15.minutes,
                let template = CLKComplicationTemplateModularSmallStackText(context: context)
            {
                handler(CLKComplicationTimelineEntry(date: date, complicationTemplate: template))
            } else {
                handler(nil)
            }
        default:
            handler(nil)
        }
    }
    
    func getTimelineEntriesForComplication(complication: CLKComplication, beforeDate date: NSDate, limit: Int, withHandler handler: (([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries prior to the given date
        handler(nil)
    }
    
    func getTimelineEntriesForComplication(complication: CLKComplication, afterDate date: NSDate, limit: Int, withHandler handler: (([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries after to the given date
        if let context = DeviceDataManager.sharedManager.lastContextData,
            glucoseDate = context.glucoseDate where glucoseDate.timeIntervalSinceDate(date) > 0,
            let template = CLKComplicationTemplateModularSmallStackText(context: context)
        {
            handler([CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)])
        } else {
            handler(nil)
        }
    }

    func requestedUpdateDidBegin() {
        DeviceDataManager.sharedManager.updateComplicationDataIfNeeded()
    }

    func requestedUpdateBudgetExhausted() {
        DiagnosticLogger()?.addError(#function, fromSource: "ClockKit")
    }

    // MARK: - Update Scheduling
    
    func getNextRequestedUpdateDateWithHandler(handler: (NSDate?) -> Void) {
        // Call the handler with the date when you would next like to be given the opportunity to update your complication content
        handler(NSDate(timeIntervalSinceNow: NSTimeInterval(2 * 60 * 60)))
    }
    
    // MARK: - Placeholder Templates
    
    func getPlaceholderTemplateForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTemplate?) -> Void) {
        switch complication.family {
        case .ModularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()

            template.line1TextProvider = CLKSimpleTextProvider(text: "--", shortText: "--", accessibilityLabel: "No glucose value available")
            template.line2TextProvider = CLKSimpleTextProvider(text: "mg/dL")

            handler(template)
        default:
            handler(nil)
        }
    }
    
}
