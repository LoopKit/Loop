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
import LoopCore

extension CLKComplicationTemplate {

    static func templateForFamily(
        _ family: CLKComplicationFamily,
        from context: WatchContext,
        at date: Date,
        recencyInterval: TimeInterval,
        chartGenerator makeChart: () -> UIImage?
    ) -> CLKComplicationTemplate? {
        guard let glucose = context.glucose, let unit = context.displayGlucoseUnit else {
            return nil
        }
        
        return templateForFamily(family,
            glucose: glucose,
            unit: unit,
            glucoseDate: context.glucoseDate,
            trend: context.glucoseTrend,
            eventualGlucose: context.eventualGlucose,
            at: date,
            loopLastRunDate: context.loopLastRunDate,
            recencyInterval: recencyInterval,
            chartGenerator: makeChart)
    }

    static func templateForFamily(
        _ family: CLKComplicationFamily,
        glucose: HKQuantity,
        unit: HKUnit,
        glucoseDate: Date?,
        trend: GlucoseTrend?,
        eventualGlucose: HKQuantity?,
        at date: Date,
        loopLastRunDate: Date?,
        recencyInterval: TimeInterval,
        chartGenerator makeChart: () -> UIImage?
    ) -> CLKComplicationTemplate? {

        let formatter = NumberFormatter.glucoseFormatter(for: unit)
        
        guard let glucoseDate = glucoseDate else {
            return nil
        }
        
        let glucoseString: String
        let trendString: String
        
        let isGlucoseStale = date.timeIntervalSince(glucoseDate) > recencyInterval

        if isGlucoseStale {
            glucoseString = NSLocalizedString("---", comment: "No glucose value representation (3 dashes for mg/dL; no spaces as this will get truncated in the watch complication)")
            trendString = ""
        } else {
            guard let formattedGlucose = formatter.string(from: glucose.doubleValue(for: unit)) else {
                return nil
            }
            glucoseString = formattedGlucose
            trendString = trend?.symbol ?? " "
        }
        
        let loopCompletionFreshness = LoopCompletionFreshness(lastCompletion: loopLastRunDate, at: date)
        
        let tintColor: UIColor
        
        switch loopCompletionFreshness {
        case .fresh:
            tintColor = .tintColor
        case .aging:
            tintColor = .agingColor
        case .stale:
            tintColor = .staleColor
        }

        let glucoseAndTrend = "\(glucoseString)\(trendString)"
        var accessibilityStrings = [glucoseString]

        if let trend = trend {
            accessibilityStrings.append(trend.localizedDescription)
        }

        let glucoseAndTrendText = CLKSimpleTextProvider(text: glucoseAndTrend, shortText: glucoseString, accessibilityLabel: accessibilityStrings.joined(separator: ", "))
        
        let timeText: CLKTextProvider
        
        if let loopLastRunDate = loopLastRunDate {
            timeText = CLKRelativeDateTextProvider(date: loopLastRunDate, style: .natural, units: [.minute, .hour, .day])
        } else {
            timeText = CLKTextProvider(format: "")
        }
        timeText.tintColor = tintColor

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText(line1TextProvider: glucoseAndTrendText, line2TextProvider: timeText)
            template.highlightLine2 = true
            return template
        case .modularLarge:
            return CLKComplicationTemplateModularLargeTallBody(headerTextProvider: timeText, bodyTextProvider: glucoseAndTrendText)
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallSimpleText(textProvider: CLKSimpleTextProvider(text: glucoseString))
        case .extraLarge:
            return CLKComplicationTemplateExtraLargeStackText(line1TextProvider: glucoseAndTrendText, line2TextProvider: timeText)
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: CLKSimpleTextProvider(text: glucoseString))
        case .utilitarianLarge:
            var eventualGlucoseText = ""
            if  let eventualGlucose = eventualGlucose,
                let eventualGlucoseString = formatter.string(from: eventualGlucose.doubleValue(for: unit))
            {
                eventualGlucoseText = eventualGlucoseString
            }

            let format = NSLocalizedString("UtilitarianLargeFlat", tableName: "ckcomplication", comment: "Utilitarian large flat format string (1: Glucose & Trend symbol) (2: Eventual Glucose) (3: Time)")

            return CLKComplicationTemplateUtilitarianLargeFlat(
                textProvider: CLKSimpleTextProvider(text: String(format: format, arguments: [
                    glucoseAndTrend,
                    eventualGlucoseText,
                    timeFormatter.string(from: glucoseDate)
                ]
            )))
        case .graphicCorner:
            if #available(watchOSApplicationExtension 5.0, *) {
                return CLKComplicationTemplateGraphicCornerStackText(innerTextProvider: timeText, outerTextProvider: glucoseAndTrendText)
            } else {
                return nil
            }
        case .graphicCircular:
            if #available(watchOSApplicationExtension 5.0, *) {
                return CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText(
                    gaugeProvider: CLKSimpleGaugeProvider(style: .fill, gaugeColor: tintColor, fillFraction: 1),
                    bottomTextProvider: CLKSimpleTextProvider(text: trendString),
                    centerTextProvider: CLKSimpleTextProvider(text: glucoseString)
                )
            } else {
                return nil
            }
        case .graphicBezel:
            if #available(watchOSApplicationExtension 5.0, *) {
                guard
                    let circularTemplate = templateForFamily(.graphicCircular,
                                                             glucose: glucose,
                                                             unit: unit,
                                                             glucoseDate: glucoseDate,
                                                             trend: trend,
                                                             eventualGlucose: eventualGlucose,
                                                             at: date,
                                                             loopLastRunDate: loopLastRunDate,
                                                             recencyInterval: recencyInterval,
                                                             chartGenerator: makeChart
                        ) as? CLKComplicationTemplateGraphicCircular
                else {
                    fatalError("\(#function) invoked with .graphicCircular must return a subclass of CLKComplicationTemplateGraphicCircular")
                }
                return CLKComplicationTemplateGraphicBezelCircularText(circularTemplate: circularTemplate, textProvider: timeText)
            } else {
                return nil
            }
        case .graphicRectangular:
            if #available(watchOSApplicationExtension 5.0, *) {
                return CLKComplicationTemplateGraphicRectangularLargeImage(
                    textProvider: CLKTextProvider(byJoining: [glucoseAndTrendText, timeText], separator: " "),
                    imageProvider: CLKFullColorImageProvider(fullColorImage: makeChart() ?? UIImage())
                )
            } else {
                return nil
            }
        case .graphicExtraLarge:
            if #available(watchOSApplicationExtension 5.0, *) {
                return CLKComplicationTemplateGraphicExtraLargeCircularOpenGaugeSimpleText(
                    gaugeProvider: CLKSimpleGaugeProvider(style: .fill, gaugeColor: tintColor, fillFraction: 1),
                    bottomTextProvider: CLKSimpleTextProvider(text: trendString),
                    centerTextProvider: CLKSimpleTextProvider(text: glucoseString)
                )
            } else {
                return nil
            }
        @unknown default:
            return nil
        }
    }
}
