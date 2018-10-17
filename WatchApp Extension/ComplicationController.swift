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
        if let date = ExtensionDelegate.shared().loopManager.activeContext?.glucoseDate {
            handler(date)
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = ExtensionDelegate.shared().loopManager.activeContext?.glucoseDate {
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
        let entry: CLKComplicationTimelineEntry?

        if  let context = ExtensionDelegate.shared().loopManager.activeContext,
            let glucoseDate = context.glucoseDate,
            glucoseDate.timeIntervalSinceNow.minutes >= -15,
            let template = CLKComplicationTemplate.templateForFamily(complication.family, from: context)
        {
            template.tintColor = UIColor.tintColor
            entry = CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)
        } else if let image = CLKComplicationTemplate.imageTemplate(for: complication.family) {
            entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: image)
        } else {
            entry = nil
        }

        handler(entry)
    }
    
    func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries prior to the given date
        handler(nil)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries after to the given date
        let entries: [CLKComplicationTimelineEntry]?

        if  let context = ExtensionDelegate.shared().loopManager.activeContext,
            let glucoseDate = context.glucoseDate
        {
            if glucoseDate.timeIntervalSince(date) > 0,
                let template = CLKComplicationTemplate.templateForFamily(complication.family, from: context)
            {
                template.tintColor = UIColor.tintColor
                entries = [CLKComplicationTimelineEntry(date: glucoseDate, complicationTemplate: template)]
            } else {
                entries = []
            }

            if let image = CLKComplicationTemplate.imageTemplate(for: complication.family) {
                entries?.append(CLKComplicationTimelineEntry(date: glucoseDate.addingTimeInterval(.hours(1)), complicationTemplate: image))
            }
        } else {
            entries = nil
        }

        handler(entries)
    }
}
