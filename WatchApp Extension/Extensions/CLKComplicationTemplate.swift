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

        var glucoseStrings = [glucoseString]
        var accessibilityStrings = [glucoseString]
        var eventualGlucoseText: CLKSimpleTextProvider?

        if let trend = context.glucoseTrend {
            glucoseStrings.append(trend.symbol)
            accessibilityStrings.append(trend.localizedDescription)
        }

        if  let eventualGlucose = context.eventualGlucose,
            let eventualGlucoseString = formatter.string(from: NSNumber(value: eventualGlucose.doubleValue(for: unit)))
        {
            eventualGlucoseText = CLKSimpleTextProvider(text: eventualGlucoseString)
        }

        let glucoseText = CLKSimpleTextProvider(text: glucoseStrings.joined(), shortText: glucoseString, accessibilityLabel: accessibilityStrings.joined(separator: ", "))
        let timeText = CLKTimeTextProvider(date: date)

        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = glucoseText
            template.line2TextProvider = timeText
            return template
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = glucoseText
            return template
        case .extraLarge:
            let template = CLKComplicationTemplateExtraLargeStackText()
            template.line1TextProvider = glucoseText
            template.line2TextProvider = timeText
            return template
        case .utilitarianSmallFlat:
            let template = CLKComplicationTemplateUtilitarianSmallFlat()
            template.textProvider = CLKSimpleTextProvider.localizableTextProvider(withStringsFileFormatKey: "UtilitarianSmallFlat", textProviders: [glucoseText, timeText])
            return template
        case .utilitarianLarge:
            let template = CLKComplicationTemplateUtilitarianLargeFlat()
            let providers: [CLKTextProvider?] = [glucoseText, eventualGlucoseText, timeText]

            template.textProvider = CLKSimpleTextProvider.localizableTextProvider(withStringsFileFormatKey: "UtilitarianLargeFlat", textProviders: providers.flatMap({ $0 }))
            return template
        default:
            return nil
        }
    }
}
