//
//  CLKComplicationTemplate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit
import HealthKit
import LoopKit
import Foundation


extension CLKComplicationTemplate {

    static func templateForFamily(_ family: CLKComplicationFamily, from context: WatchContext) -> CLKComplicationTemplate? {
        guard let glucose = context.glucose, let unit = context.preferredGlucoseUnit else {
            return nil
        }

        return templateForFamily(family, glucose: glucose, unit: unit, date: context.glucoseDate, trend: context.glucoseTrend, eventualGlucose: context.eventualGlucose)
    }

    static func templateForFamily(_ family: CLKComplicationFamily, glucose: HKQuantity, unit: HKUnit, date: Date?, trend: GlucoseTrend?, eventualGlucose: HKQuantity?) -> CLKComplicationTemplate? {

        let formatter = NumberFormatter.glucoseFormatter(for: unit)

        guard let glucoseString = formatter.string(from: glucose.doubleValue(for: unit)),
            let date = date else
        {
            return nil
        }

        let glucoseAndTrend = "\(glucoseString)\(trend?.symbol ?? " ")"
        var accessibilityStrings = [glucoseString]

        if let trend = trend {
            accessibilityStrings.append(trend.localizedDescription)
        }

        let glucoseAndTrendText = CLKSimpleTextProvider(text: glucoseAndTrend, shortText: glucoseString, accessibilityLabel: accessibilityStrings.joined(separator: ", "))
        let timeText = CLKRelativeDateTextProvider(date: date, style: .natural, units: .minute)

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        
        switch family {
        case .graphicCorner:
            // ***************************************
            // ** Apple Watch Series 4 Complication **
            // ***************************************
            // Corner Text
            // Outer Text: Current Glucose and Trend
            // Inner Text: timeText

            if #available(watchOSApplicationExtension 5.0, *) {
                let cornerTemplate = CLKComplicationTemplateGraphicCornerStackText()
                cornerTemplate.outerTextProvider = glucoseAndTrendText
                cornerTemplate.outerTextProvider.tintColor = .green
                cornerTemplate.innerTextProvider = timeText
                return cornerTemplate
            } else {
                // Fallback on earlier versions
                return  nil
            }
        case .graphicCircular:
            // ***************************************
            // ** Apple Watch Series 4 Complication **
            // ***************************************
            // Circular Gauge
            // Full Ring
            // Current Glucose in Center, Trend Arrow Below
            // * future enhancement - update gauge colors to reflect loop status, or time in range for the day
            if #available(watchOSApplicationExtension 5.0, *) {
                let circularTemplate = CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText()
                circularTemplate.gaugeProvider = CLKSimpleGaugeProvider(style: .fill, gaugeColor: .green, fillFraction: 1)
                circularTemplate.centerTextProvider = CLKSimpleTextProvider(text: glucoseString)
                circularTemplate.bottomTextProvider = CLKSimpleTextProvider(text: (trend?.symbol ?? " "))
                return circularTemplate
            } else {
                // Fallback on earlier versions
                return nil
            }
        case .graphicRectangular, .graphicBezel:
            return nil
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
            if  let eventualGlucose = eventualGlucose,
                let eventualGlucoseString = formatter.string(from: eventualGlucose.doubleValue(for: unit))
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
