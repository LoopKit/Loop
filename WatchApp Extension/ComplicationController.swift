//
//  ComplicationController.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit
import WatchKit


final class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Timeline Configuration
    
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.backward])
    }
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = ExtensionDelegate.shared().lastContext?.glucoseDate {
            handler(date as Date)
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = ExtensionDelegate.shared().lastContext?.glucoseDate {
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

        var templateEntry: CLKComplicationTimelineEntry?
        switch complication.family {
        case .modularSmall:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let date = context.glucoseDate, date.timeIntervalSinceNow.minutes >= -15,
                let template = CLKComplicationTemplateModularSmallStackText(line1: glucoseString, date: date)
            {
                templateEntry = CLKComplicationTimelineEntry(date: date, complicationTemplate: template)
            } else {
                templateEntry = nil
            }
        case .modularLarge:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let date = context.glucoseDate, date.timeIntervalSinceNow.minutes >= -15,
                let template = CLKComplicationTemplateModularLargeTallBody(line1: glucoseString, date: date)
            {
                templateEntry = CLKComplicationTimelineEntry(date: date, complicationTemplate: template)
            } else {
                templateEntry = nil
            }
        case .circularSmall:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let date = context.glucoseDate, date.timeIntervalSinceNow.minutes >= -15,
                let template = CLKComplicationTemplateCircularSmallStackText(line1: glucoseString, date: date)
            {
                templateEntry = CLKComplicationTimelineEntry(date: date, complicationTemplate: template)
            } else {
                templateEntry = nil
            }
        case .extraLarge:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let date = context.glucoseDate, date.timeIntervalSinceNow.minutes >= -15,
                let template = CLKComplicationTemplateExtraLargeStackText(line1: glucoseString, date: date)
            {
                templateEntry = CLKComplicationTimelineEntry(date: date, complicationTemplate: template)
            } else {
                templateEntry = nil
            }
        default:
            templateEntry = nil
        }
        handler(templateEntry)
    }
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries prior to the given date
        handler(nil)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries after to the given date
        var templateEntry: [CLKComplicationTimelineEntry]?
        switch complication.family {
        case .modularSmall:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let glucoseDate = context.glucoseDate, glucoseDate.timeIntervalSince(date) > 0,
                let template = CLKComplicationTemplateModularSmallStackText(line1: glucoseString, date: glucoseDate)
            {
                templateEntry = [CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)]
            } else {
                templateEntry = nil
            }
        case .modularLarge:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let glucoseDate = context.glucoseDate, glucoseDate.timeIntervalSince(date) > 0,
                let template = CLKComplicationTemplateModularLargeTallBody(line1: glucoseString, date: glucoseDate)
            {
                templateEntry = [CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)]
            } else {
                templateEntry = nil
            }
        case .circularSmall:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let glucoseDate = context.glucoseDate, glucoseDate.timeIntervalSince(date) > 0,
                let template = CLKComplicationTemplateCircularSmallStackText(line1: glucoseString, date: glucoseDate)
            {
                templateEntry = [CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)]
            } else {
                templateEntry = nil
            }
        case .extraLarge:
            if let context = ExtensionDelegate.shared().lastContext,
                let glucose = context.glucose,
                let unit = context.preferredGlucoseUnit,
                let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
                let glucoseDate = context.glucoseDate, glucoseDate.timeIntervalSince(date) > 0,
                let template = CLKComplicationTemplateExtraLargeStackText(line1: glucoseString, date: glucoseDate)
            {
                templateEntry = [CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)]
            } else {
                templateEntry = nil
            }
        default:
            templateEntry = nil
        }
        handler(templateEntry)
    }

    // MARK: - Placeholder Templates

    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        switch complication.family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()

            template.line1TextProvider = CLKSimpleTextProvider(text: "--", shortText: "--", accessibilityLabel: "No glucose value available")
            template.line2TextProvider = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "mg/dL")

            handler(template)
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeTallBody()
            
            template.bodyTextProvider = CLKSimpleTextProvider(text: "--", shortText: "--", accessibilityLabel: "No glucose value available")
            template.headerTextProvider = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "mg/dL")
            
            handler(template)
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallStackText()
            
            template.line1TextProvider = CLKSimpleTextProvider(text: "--", shortText: "--", accessibilityLabel: "No glucose value available")
            template.line2TextProvider = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "mg/dL")
            
            handler(template)
        case .extraLarge:
            let template = CLKComplicationTemplateExtraLargeStackText()
            
            template.line1TextProvider = CLKSimpleTextProvider(text: "--", shortText: "--", accessibilityLabel: "No glucose value available")
            template.line2TextProvider = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "mg/dL")
            
            handler(template)
        default:
            handler(nil)
        }
    }
}
