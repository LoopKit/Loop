//
//  ComplicationController.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit


final class ComplicationController: NSObject, CLKComplicationDataSource {
    
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

    private lazy var formatter = NSNumberFormatter()

    func getCurrentTimelineEntryForComplication(complication: CLKComplication, withHandler handler: ((CLKComplicationTimelineEntry?) -> Void)) {

        switch complication.family {
        case .ModularSmall:
            if let context = DeviceDataManager.sharedManager.lastContextData,
                glucose = context.glucose,
                unit = context.preferredGlucoseUnit,
                glucoseString = formatter.stringFromNumber(glucose.doubleValueForUnit(unit)),
                date = context.glucoseDate where date.timeIntervalSinceNow.minutes >= -15,
                let template = CLKComplicationTemplateModularSmallStackText(line1: glucoseString, date: date)
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
            glucose = context.glucose,
            unit = context.preferredGlucoseUnit,
            glucoseString = formatter.stringFromNumber(glucose.doubleValueForUnit(unit)),
            glucoseDate = context.glucoseDate where glucoseDate.timeIntervalSinceDate(date) > 0,
            let template = CLKComplicationTemplateModularSmallStackText(line1: glucoseString, date: glucoseDate)
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
        // TODO: os_log_info in iOS 10
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
