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
        case .graphicCorner, .graphicCircular, .graphicRectangular, .graphicBezel:
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

    static func imageTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .modularSmall:
            guard let image = UIImage(named: "Modular") else { return nil }

            let template = CLKComplicationTemplateModularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: image)
            return template
        case .modularLarge:
            return nil
        case .utilitarianSmall:
            guard let image = UIImage(named: "Utility") else { return nil }

            let template = CLKComplicationTemplateUtilitarianSmallSquare()
            template.imageProvider = CLKImageProvider(onePieceImage: image)
            return template
        case .utilitarianSmallFlat:
            return nil
        case .utilitarianLarge:
            return nil
        case .circularSmall:
            guard let image = UIImage(named: "Circular") else { return nil }

            let template = CLKComplicationTemplateCircularSmallSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: image)
            return template
        case .extraLarge:
            guard let image = UIImage(named: "Extra Large") else { return nil }

            let template = CLKComplicationTemplateExtraLargeSimpleImage()
            template.imageProvider = CLKImageProvider(onePieceImage: image)
            return template
        case .graphicCorner:
            guard #available(watchOSApplicationExtension 5.0, *), let image = UIImage(named: "Graphic Corner") else { return nil }

            let template = CLKComplicationTemplateGraphicCornerCircularImage()
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: image)
            return template
        case .graphicBezel:
            guard #available(watchOSApplicationExtension 5.0, *), let image = UIImage(named: "Graphic Bezel") else { return nil }

            let template = CLKComplicationTemplateGraphicBezelCircularText()
            template.circularTemplate = {
                let template = CLKComplicationTemplateGraphicCircularImage()
                template.imageProvider = CLKFullColorImageProvider(fullColorImage: image)
                return template
            }()
            return template
        case .graphicCircular:
            guard #available(watchOSApplicationExtension 5.0, *), let image = UIImage(named: "Graphic Circular") else { return nil }

            let template = CLKComplicationTemplateGraphicCircularImage()
            template.imageProvider = CLKFullColorImageProvider(fullColorImage: image)
            return template
        case .graphicRectangular:
            return nil
        }
    }
}
