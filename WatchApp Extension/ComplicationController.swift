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
            handler(date)
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = ExtensionDelegate.shared().lastContext?.glucoseDate {
            handler(date)
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
        if  let context = ExtensionDelegate.shared().lastContext,
            let glucoseDate = context.glucoseDate,
            glucoseDate.timeIntervalSinceNow.minutes >= -15,
            let template = CLKComplicationTemplate.templateForFamily(complication.family, from: context)
        {
            template.tintColor = UIColor.tintColor
            handler(CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template))
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries prior to the given date
        handler(nil)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries after to the given date
        if  let context = ExtensionDelegate.shared().lastContext,
            let glucoseDate = context.glucoseDate,
            glucoseDate.timeIntervalSince(date) > 0,
            let template = CLKComplicationTemplate.templateForFamily(complication.family, from: context)
        {
            template.tintColor = UIColor.tintColor
            handler([CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)])
        } else {
            handler(nil)
        }
    }

    // MARK: - Placeholder Templates

    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {

        let template: CLKComplicationTemplate?
        
        let glucoseText = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "120↘︎", shortTextKey: "120")
        let timeText = CLKRelativeDateTextProvider(date: Date(), style: .natural, units: .minute)

        switch complication.family {
        case .modularSmall:
            let modularSmall = CLKComplicationTemplateModularSmallStackText()
            modularSmall.line1TextProvider = glucoseText
            modularSmall.line2TextProvider = timeText
            template = modularSmall
        case .modularLarge:
            let modularSmall = CLKComplicationTemplateModularLargeTallBody()
            modularSmall.bodyTextProvider = glucoseText
            modularSmall.headerTextProvider = timeText
            template = modularSmall
        case .circularSmall:
            let circularSmall = CLKComplicationTemplateCircularSmallSimpleText()
            circularSmall.textProvider = glucoseText
            template = circularSmall
        case .extraLarge:
            let extraLarge = CLKComplicationTemplateExtraLargeStackText()
            extraLarge.line1TextProvider = glucoseText
            extraLarge.line2TextProvider = timeText
            template = extraLarge
        case .utilitarianSmall, .utilitarianSmallFlat:
            let utilitarianSmallFlat = CLKComplicationTemplateUtilitarianSmallFlat()
            utilitarianSmallFlat.textProvider = glucoseText
            template = utilitarianSmallFlat
        case .utilitarianLarge:
            let utilitarianLarge = CLKComplicationTemplateUtilitarianLargeFlat()
            let eventualGlucoseText = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "75")
            utilitarianLarge.textProvider = CLKSimpleTextProvider.localizableTextProvider(withStringsFileFormatKey: "UtilitarianLargeFlat", textProviders: [glucoseText, eventualGlucoseText, CLKTimeTextProvider(date: Date())])
            template = utilitarianLarge
        }

        template?.tintColor = UIColor.tintColor
        handler(template)
    }
}
