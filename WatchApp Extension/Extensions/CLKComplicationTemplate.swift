//
//  CLKComplicationTemplate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit
import Foundation


extension CLKComplicationTemplate {

    static func templateForFamily(_ family: CLKComplicationFamily, from context: WatchContext) -> CLKComplicationTemplate? {

        guard let glucose = context.glucose,
            let unit = context.preferredGlucoseUnit
        else {
            return nil
        }

        let formatter = NumberFormatter.glucoseFormatter(for: unit)

        guard let glucoseString = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))),
            let date = context.glucoseDate else
        {
            return nil
        }

        let glucoseAndTrend = "\(glucoseString)\(context.glucoseTrend?.symbol ?? " ")"
        var accessibilityStrings = [glucoseString]

        if let trend = context.glucoseTrend {
            accessibilityStrings.append(trend.localizedDescription)
        }

        let glucoseAndTrendText = CLKSimpleTextProvider(text: glucoseAndTrend, shortText: glucoseString, accessibilityLabel: accessibilityStrings.joined(separator: ", "))
        let timeText = CLKRelativeDateTextProvider(date: date, style: .natural, units: .minute)

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = glucoseAndTrendText
            template.line2TextProvider = timeText
            return template
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeTallBody()
            template.bodyTextProvider = glucoseAndTrendText
            template.headerTextProvider = timeText
            return template
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: glucoseString)
            return template
        case .extraLarge:
            let template = CLKComplicationTemplateExtraLargeStackText()
            template.line1TextProvider = glucoseAndTrendText
            template.line2TextProvider = timeText
            return template
        case .utilitarianSmall, .utilitarianSmallFlat:
            let template = CLKComplicationTemplateUtilitarianSmallFlat()
            template.textProvider = CLKSimpleTextProvider(text: glucoseString)

            return template
        case .utilitarianLarge:
            var eventualGlucoseText = ""
            if  let eventualGlucose = context.eventualGlucose,
                let eventualGlucoseString = formatter.string(from: NSNumber(value: eventualGlucose.doubleValue(for: unit)))
            {
                eventualGlucoseText = eventualGlucoseString
            }

            let template = CLKComplicationTemplateUtilitarianLargeFlat()
            let format = NSLocalizedString("UtilitarianLargeFlat", tableName: "ckcomplication", comment: "Utilitarian large flat format string (1: Glucose & Trend symbol) (2: Eventual Glucose) (3: Time)")

            template.textProvider = CLKSimpleTextProvider(text: String(format: format, arguments: [
                    glucoseAndTrend,
                    eventualGlucoseText,
                    timeFormatter.string(from: date)
                ]
            ))
            return template
        }
    }
}
