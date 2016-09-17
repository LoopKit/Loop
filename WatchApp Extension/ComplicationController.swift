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
    
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.backward])
    }
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = DeviceDataManager.sharedManager.lastContextData?.glucoseDate {
            handler(date as Date)
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = DeviceDataManager.sharedManager.lastContextData?.glucoseDate {
            handler(date as Date)
        } else {
            handler(nil)
        }
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.hideOnLockScreen)
    }
    
    // MARK: - Timeline Population

    private lazy var formatter = NumberFormatter()

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: (@escaping (CLKComplicationTimelineEntry?) -> Void)) {

        switch complication.family {
        case .modularSmall:
            if let context = DeviceDataManager.sharedManager.lastContextData,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let date = context.glucoseDate, date.timeIntervalSinceNow.minutes >= -15,
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
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries prior to the given date
        handler(nil)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries after to the given date
        if let context = DeviceDataManager.sharedManager.lastContextData,
            let glucose = context.glucose,
            let unit = context.preferredGlucoseUnit,
            let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
            let glucoseDate = context.glucoseDate, glucoseDate.timeIntervalSince(date) > 0,
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
    
    func getNextRequestedUpdateDate(handler: @escaping (Date?) -> Void) {
        // Call the handler with the date when you would next like to be given the opportunity to update your complication content
        handler(Date(timeIntervalSinceNow: TimeInterval(2 * 60 * 60)))
    }
    
    // MARK: - Placeholder Templates
    
    func getPlaceholderTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        switch complication.family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()

            template.line1TextProvider = CLKSimpleTextProvider(text: "--", shortText: "--", accessibilityLabel: "No glucose value available")
            template.line2TextProvider = CLKSimpleTextProvider(text: "mg/dL")

            handler(template)
        default:
            handler(nil)
        }
    }

}
