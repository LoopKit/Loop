//
//  CriticalEventLogExportViewModel.swift
//  Loop
//
//  Created by Darin Krauss on 7/10/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import os.log
import Foundation
import Combine
import SwiftUI
import LoopKit

protocol CriticalEventLogExporterFactory {
    func createExporter(to url: URL) -> CriticalEventLogExporter
}

extension CriticalEventLogExportManager: CriticalEventLogExporterFactory {}

public class CriticalEventLogExportViewModel: ObservableObject, Identifiable, CriticalEventLogExporterDelegate {
    @Published var isExporting: Bool = false
    @Published var showingSuccess: Bool = false
    @Published var showingShare: Bool = false
    @Published var showingError: Bool = false
    @Published var progress: Double = 0 {
        didSet {
            let now = Date()
            if self.progressStartDate == nil {
                self.progressStartDate = now
            }

            // If no progress in the last few seconds, then means we were backgrounded, so discount that gap (move start forward by same)
            if let progressLatestDate = self.progressLatestDate {
                let progressLatestDuration = now.timeIntervalSince(progressLatestDate)
                if progressLatestDuration > self.progressDurationBackgroundMaximum {
                    self.progressStartDate! += progressLatestDuration
                }
            }

            self.progressLatestDate = now

            // If no progress, then we have no idea when we will finish and bail (prevents divide by zero)
            guard progress > 0 else {
                self.remainingDuration = nil
                return
            }

            // If we haven't been exporting for long, then remaining duration may be wildly inaccurate so just bail
            let progressDuration = now.timeIntervalSince(self.progressStartDate!)
            guard progressDuration > self.progressDurationMinimum else {
                self.remainingDuration = nil
                return
            }

            self.remainingDuration = self.remainingDurationAsString(progressDuration / progress - progressDuration)
        }
    }
    @Published var remainingDuration: String?

    var activityItems: [UIActivityItemSource] = []

    private var progressPublisher = PassthroughSubject<Double, Never>()
    private var progressStartDate: Date?
    private var progressLatestDate: Date?

    private let exporterFactory: CriticalEventLogExporterFactory
    private var exporter: CriticalEventLogExporter?

    private var cancellables: Set<AnyCancellable> = []

    private let log = OSLog(category: "CriticalEventLogExportManager")

    init(exporterFactory: CriticalEventLogExporterFactory) {
        self.exporterFactory = exporterFactory

        progressPublisher
            .removeDuplicates()
            .throttle(for: .seconds(0.25), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.progress = $0 }
            .store(in: &cancellables)
    }

    func export() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !isExporting else {
            return
        }

        self.isExporting = true

        self.showingSuccess = false
        self.showingShare = false
        self.showingError = false
        self.progress = 0
        self.remainingDuration = nil

        self.progressStartDate = nil
        self.progressLatestDate = nil
        self.activityItems = []

        let filename = String(format: NSLocalizedString("Export-%1$@", comment: "The export file name formatted string (1: timestamp)"), self.timestampFormatter.string(from: Date()))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename).appendingPathExtension("zip")

        var exporter = exporterFactory.createExporter(to: url)
        exporter.delegate = self

        self.exporter = exporter

        exporter.export() { error in
            DispatchQueue.main.async {
                guard !exporter.isCancelled else {
                    return
                }

                if let error = error {
                    self.log.error("Failure during critical event log export: %{public}@", String(describing: error))
                    self.showingError = true
                } else {
                    self.progress = 1.0
                    self.activityItems = [CriticalEventLogExportActivityItemSource(url: url)]
                    self.showingSuccess = true
                    self.showingShare = true
                }
            }
        }
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))

        self.exporter?.cancel()
        self.exporter = nil
        self.activityItems = []
        self.isExporting = false
    }

    // MARK: - CriticalEventLogExporterDelegate

    private let progressDurationBackgroundMaximum: TimeInterval = .seconds(5)
    private let progressDurationMinimum: TimeInterval = .seconds(5)

    public func exportDidProgress(_ progress: Double) {
        progressPublisher.send(progress)
    }

    // The default duration formatter formats a duration in the range of X minutes through X minutes and 59 seconds as
    // "About X minutes remaining". Offset calculation to effectively change the range to X+1 minutes and 30 seconds through
    // X minutes and 29 seconds to address misleading messages when duration is two minutes down to complete.
    private let remainingDurationApproximationOffset: TimeInterval = 30

    private func remainingDurationAsString(_ remainingDuration: TimeInterval) -> String? {
        switch remainingDuration {
        case 0..<15:
            return NSLocalizedString("A few seconds remaining", comment: "Estimated remaining duration with a few seconds")
        case 15..<60:
            return NSLocalizedString("Less than a minute remaining", comment: "Estimated remaining duration with less than a minute")
        default:
            guard let durationString = durationFormatter.string(from: remainingDuration + remainingDurationApproximationOffset) else {
                return nil
            }
            return String(format: NSLocalizedString("%@ remaining", comment: "Estimated remaining duration with more than a minute"), durationString)
        }
    }

    private var durationFormatter: DateComponentsFormatter { Self.durationFormatter }

    private var timestampFormatter: ISO8601DateFormatter { Self.timestampFormatter }

    private static var durationFormatter: DateComponentsFormatter = {
        let durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute]
        durationFormatter.includesApproximationPhrase = true
        durationFormatter.unitsStyle = .full
        return durationFormatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = calendar.timeZone
        timestampFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return timestampFormatter
    }()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

fileprivate class CriticalEventLogExportActivityItemSource: NSObject, UIActivityItemSource {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - UIActivityItemSource

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return url.lastPathComponent
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "com.pkware.zip-archive"
    }
}
