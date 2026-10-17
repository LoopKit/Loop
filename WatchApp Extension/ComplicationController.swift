//
//  ComplicationController.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit
import WatchKit
import LoopKit
import os.log
import LoopAlgorithm

final class ComplicationController: NSObject, CLKComplicationDataSource {
    
    private let log = OSLog(category: "ComplicationController")

    // MARK: - Timeline Configuration
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = LoopDataManager.shared.activeContext?.glucoseDate {
            handler(date)
        } else {
            handler(nil)
        }
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        if let date = LoopDataManager.shared.activeContext?.glucoseDate {
            handler(date)
        } else {
            handler(nil)
        }
    }

    func complicationDescriptors() async -> [CLKComplicationDescriptor] {
        return [
            CLKComplicationDescriptor(
                identifier: "glucosegraph",
                displayName: "Glucose Graph",
                supportedFamilies: [.graphicRectangular, .graphicExtraLarge,]
            ),
            CLKComplicationDescriptor(
                identifier: "glucosegraph",
                displayName: "Loop Status",
                supportedFamilies: [.circularSmall, .extraLarge, .graphicBezel, .graphicCircular, .graphicCorner, .modularLarge, .modularSmall, .utilitarianLarge, .utilitarianSmall, .utilitarianSmallFlat]
            )
        ]
    }

    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.hideOnLockScreen)
    }
    
    // MARK: - Timeline Population

    private let chartManager = ComplicationChartManager()

    private func updateChartManagerIfNeeded(completion: @escaping () -> Void) {
        guard
            #available(watchOSApplicationExtension 5.0, *),
            let activeComplications = CLKComplicationServer.sharedInstance().activeComplications,
            activeComplications.contains(where: { $0.family == .graphicRectangular })
        else {
            completion()
            return
        }

        Task { @MainActor in
            let chartData = await LoopDataManager.shared.generateChartData()
            self.chartManager.data = chartData
            completion()
        }
    }

    func makeChart() -> UIImage? {
        // c.f. https://developer.apple.com/design/human-interface-guidelines/watchos/icons-and-images/complication-images/
        let size: CGSize = {
            switch WKInterfaceDevice.current().screenBounds.width {
            case let x where x > 180:  // 44mm
                return CGSize(width: 171.0, height: 54.0)
            default: // 40mm
                return CGSize(width: 150.0, height: 47.0)
            }
        }()

        let scale = WKInterfaceDevice.current().screenScale
        return chartManager.renderChartImage(size: size, scale: scale)
    }

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: (@escaping (CLKComplicationTimelineEntry?) -> Void)) {
        updateChartManagerIfNeeded(completion: {
            let entry: CLKComplicationTimelineEntry?
            
            let timelineDate = Date()
            
            self.log.default("Updating current complication timeline entry")
            
            if let context = LoopDataManager.shared.activeContext,
                let template = CLKComplicationTemplate.templateForFamily(complication.family,
                                                                         from: context,
                                                                         at: timelineDate,
                                                                         recencyInterval: LoopAlgorithm.inputDataRecencyInterval,
                                                                         chartGenerator: self.makeChart)
            {
                switch complication.family {
                case .graphicRectangular:
                    break
                default:
                    template.tintColor = .tintColor
                }
                entry = CLKComplicationTimelineEntry(date: timelineDate, complicationTemplate: template)
            } else {
                entry = nil
            }

            handler(entry)
        })
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: (@escaping ([CLKComplicationTimelineEntry]?) -> Void)) {
        updateChartManagerIfNeeded {
            let entries: [CLKComplicationTimelineEntry]?
            
            guard let context = LoopDataManager.shared.activeContext,
                let glucoseDate = context.glucoseDate else
            {
                handler(nil)
                return
            }
            
            var futureChangeDates: [Date] = [
                // Stale glucose date: just a second after glucose expires
                glucoseDate + LoopAlgorithm.inputDataRecencyInterval + 1,
            ]
            
            if let loopLastRunDate = context.loopLastRunDate {
                let freshnessCategories = [
                    LoopCompletionFreshness.fresh,
                    LoopCompletionFreshness.aging,
                    LoopCompletionFreshness.stale
                    ].compactMap( { $0.maxAge })
                futureChangeDates.append(contentsOf: freshnessCategories.map { loopLastRunDate + $0 + 1})
            }
            
            entries = futureChangeDates.filter { $0 > date }.compactMap({ (futureChangeDate) -> CLKComplicationTimelineEntry? in
                if let template = CLKComplicationTemplate.templateForFamily(complication.family,
                                                                            from: context,
                                                                            at: futureChangeDate,
                                                                            recencyInterval: LoopAlgorithm.inputDataRecencyInterval,
                                                                            chartGenerator: self.makeChart)
                {
                    template.tintColor = UIColor.tintColor
                    self.log.default("Adding complication timeline entry for date %{public}@", String(describing: futureChangeDate))
                    return CLKComplicationTimelineEntry(date: futureChangeDate, complicationTemplate: template)
                } else {
                    return nil
                }
            })
            
            handler(entries)
        }
    }

    // MARK: - Placeholder Templates

    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        let template = getLocalizableSampleTemplate(for: complication.family)
        handler(template)
    }

    func getLocalizableSampleTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        let glucoseAndTrendText = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "120↘︎")
        let glucoseText = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "120")
        let timeText = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "3MIN")

        switch family {
        case .modularSmall:
            return CLKComplicationTemplateModularSmallStackText(line1TextProvider: glucoseAndTrendText, line2TextProvider: timeText)
        case .modularLarge:
            return CLKComplicationTemplateModularLargeTallBody(headerTextProvider: timeText, bodyTextProvider: glucoseAndTrendText)
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallSimpleText(textProvider: glucoseAndTrendText)
        case .extraLarge:
            return CLKComplicationTemplateExtraLargeStackText(line1TextProvider: glucoseAndTrendText, line2TextProvider: timeText)
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: glucoseAndTrendText)
        case .utilitarianLarge:
            let eventualGlucoseText = CLKSimpleTextProvider.localizableTextProvider(withStringsFileTextKey: "75")
            return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: CLKSimpleTextProvider.localizableTextProvider(withStringsFileFormatKey: "UtilitarianLargeFlat", textProviders: [glucoseAndTrendText, eventualGlucoseText, CLKTimeTextProvider(date: Date())]))
        case .graphicCorner:
            if #available(watchOSApplicationExtension 5.0, *) {
                let template = CLKComplicationTemplateGraphicCornerStackText(innerTextProvider: timeText, outerTextProvider: glucoseAndTrendText)
                timeText.tintColor = .tintColor
                return template
            } else {
                return nil
            }
        case .graphicCircular:
            if #available(watchOSApplicationExtension 5.0, *) {
                return CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText(
                    gaugeProvider: CLKSimpleGaugeProvider(style: .fill, gaugeColor: .tintColor, fillFraction: 1),
                    bottomTextProvider: glucoseText,
                    centerTextProvider: CLKSimpleTextProvider(text: "↘︎")
                )
            } else {
                return nil
            }
        case .graphicBezel:
            if #available(watchOSApplicationExtension 5.0, *) {
                guard let circularTemplate = getLocalizableSampleTemplate(for: .graphicCircular) as? CLKComplicationTemplateGraphicCircular else {
                    fatalError("\(#function) invoked with .graphicCircular must return a subclass of CLKComplicationTemplateGraphicCircular")
                }
                return CLKComplicationTemplateGraphicBezelCircularText(circularTemplate: circularTemplate, textProvider: timeText)
            } else {
                return nil
            }
        case .graphicRectangular:
            if #available(watchOSApplicationExtension 5.0, *) {
                // TODO: Better placeholder image here
                return CLKComplicationTemplateGraphicRectangularLargeImage(textProvider: glucoseAndTrendText, imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage()))

            } else {
                return nil
            }
        case .graphicExtraLarge:
            if #available(watchOSApplicationExtension 5.0, *) {
                return CLKComplicationTemplateGraphicExtraLargeCircularOpenGaugeSimpleText(
                    gaugeProvider: CLKSimpleGaugeProvider(style: .fill, gaugeColor: .tintColor, fillFraction: 1),
                    bottomTextProvider: glucoseText,
                    centerTextProvider: CLKSimpleTextProvider(text: "↘︎")
                )
            } else {
                return nil
            }
        @unknown default:
            return nil
        }
    }
}

// MARK: - Migration to WidgetKit

/// Faces that show a ClockKit complication from this app are moved to its WidgetKit replacement when
/// the app updates. Both ClockKit descriptors share the identifier "glucosegraph", so they are told
/// apart by family: the graph is the one offered in the large rectangular slot.
extension ComplicationController: CLKComplicationWidgetMigrator {

    var widgetMigrator: CLKComplicationWidgetMigrator { self }

    func widgetConfiguration(from complicationDescriptor: CLKComplicationDescriptor) async -> CLKComplicationWidgetMigrationConfiguration? {
        guard let appBundle = Bundle.main.bundleIdentifier else { return nil }
        let kind = complicationDescriptor.supportedFamilies.contains(.graphicRectangular)
            ? LoopComplicationKind.glucoseGraph
            : LoopComplicationKind.loopStatus
        return CLKComplicationStaticWidgetMigrationConfiguration(kind: kind, extensionBundleIdentifier: appBundle + ".Complications")
    }
}
