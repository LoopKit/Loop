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

    static func templateForFamily(_ family: CLKComplicationFamily, from context: WatchContext, chartGenerator makeChart: () -> UIImage?) -> CLKComplicationTemplate? {
        guard let glucose = context.glucose, let unit = context.preferredGlucoseUnit else {
            return nil
        }

        return templateForFamily(family, glucose: glucose, unit: unit, date: context.glucoseDate, trend: context.glucoseTrend, eventualGlucose: context.eventualGlucose, chartGenerator: makeChart)
    }

    static func templateForFamily(
        _ family: CLKComplicationFamily,
        glucose: HKQuantity,
        unit: HKUnit,
        date: Date?,
        trend: GlucoseTrend?,
        eventualGlucose: HKQuantity?,
        chartGenerator makeChart: () -> UIImage?
    ) -> CLKComplicationTemplate? {

        let formatter = NumberFormatter.glucoseFormatter(for: unit)

        guard let glucoseString = formatter.string(from: glucose.doubleValue(for: unit)),
            let date = date else
        {
            return nil
        }

        let trendString = trend?.symbol ?? " "
        let glucoseAndTrend = "\(glucoseString)\(trendString)"
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
        case .graphicCorner:
            if #available(watchOSApplicationExtension 5.0, *) {
                let template = CLKComplicationTemplateGraphicCornerStackText()
                timeText.tintColor = .tintColor
                template.innerTextProvider = timeText
                template.outerTextProvider = glucoseAndTrendText
                return template
            } else {
                return nil
            }
        case .graphicCircular:
            if #available(watchOSApplicationExtension 5.0, *) {
                let template = CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText()
                template.centerTextProvider = CLKSimpleTextProvider(text: glucoseString)
                template.bottomTextProvider = CLKSimpleTextProvider(text: trendString)
                template.gaugeProvider = CLKSimpleGaugeProvider(style: .fill, gaugeColor: .tintColor, fillFraction: 1)
                return template
            } else {
                return nil
            }
        case .graphicBezel:
            if #available(watchOSApplicationExtension 5.0, *) {
                let template = CLKComplicationTemplateGraphicBezelCircularText()
                guard
                    let circularTemplate = templateForFamily(.graphicCircular, glucose: glucose, unit: unit, date: date, trend: trend, eventualGlucose: eventualGlucose, chartGenerator: makeChart) as? CLKComplicationTemplateGraphicCircular
                else {
                    fatalError("\(#function) invoked with .graphicCircular must return a subclass of CLKComplicationTemplateGraphicCircular")
                }
                template.circularTemplate = circularTemplate
                template.textProvider = timeText
                return template
            } else {
                return nil
            }
        case .graphicRectangular:
            if #available(watchOSApplicationExtension 5.0, *) {
                let template = CLKComplicationTemplateGraphicRectangularLargeImage()
                template.imageProvider = CLKFullColorImageProvider(fullColorImage: makeChart() ?? UIImage())
                timeText.tintColor = .tintColor
                template.textProvider = CLKTextProvider(byJoining: [glucoseAndTrendText, timeText], separator: " ")
                return template
            } else {
                return nil
            }
        }
    }
}
