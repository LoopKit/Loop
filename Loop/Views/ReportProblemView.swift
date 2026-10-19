//
//  ReportProblemView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

/// Report a Problem shown on its own, outside Settings.
struct ReportProblemModal: View {
    let viewModel: SettingsViewModel

    @Environment(\.dismissAction) private var dismiss

    var body: some View {
        NavigationView {
            ReportProblemView(
                issueReportContext: viewModel.issueReportContext,
                generateDiagnosticReport: viewModel.generateDiagnosticReport,
                criticalEventLogExportViewModel: viewModel.criticalEventLogExportViewModel
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Button to close the report a problem screen"), action: dismiss)
                }
            }
        }
    }
}

struct ReportProblemView: View {
    let issueReportContext: [String: IssueReportContextValue]
    let generateDiagnosticReport: (() async -> String)?
    let criticalEventLogExportViewModel: CriticalEventLogExportViewModel

    @Environment(\.openURL) private var openURL

    @State private var isPreparingReport = false
    @State private var reportFile: ReportFile?
    @State private var writtenReportURL: URL?

    private struct ReportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        List {
            Section {
                NavigationLink(destination: SendIssueReportView(
                    context: issueReportContext,
                    generateDiagnosticReport: generateDiagnosticReport
                )) {
                    option(
                        NSLocalizedString("Send to the Loop Developers", comment: "Report a problem option: submit an issue report to the developers"),
                        detail: NSLocalizedString("Private. Describe the problem and attach screenshots and a diagnostic report. Only the LoopKit development team can see it.", comment: "Report a problem option detail: submit an issue report to the developers")
                    )
                }

                if let generateDiagnosticReport {
                    Button(action: { shareDiagnosticReport(generateDiagnosticReport) }) {
                        HStack {
                            option(
                                NSLocalizedString("Share a Diagnostic Report", comment: "Report a problem option: share the diagnostic report yourself"),
                                detail: NSLocalizedString("Save the report or send it to someone helping you, for example on Zulip or Facebook. It contains health data such as glucose, insulin, carbs and your therapy settings.", comment: "Report a problem option detail: share the diagnostic report yourself")
                            )
                            if isPreparingReport {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isPreparingReport)
                }

                Button(action: { openURL(URL(string: "https://github.com/LoopKit/Loop/issues")!) }) {
                    option(
                        NSLocalizedString("Open a GitHub Issue", comment: "Report a problem option: open the public GitHub issues page"),
                        detail: NSLocalizedString("Public. For bugs you can describe without any personal or health data.", comment: "Report a problem option detail: open the public GitHub issues page")
                    )
                }

                NavigationLink(destination: CriticalEventLogExportView(viewModel: criticalEventLogExportViewModel)) {
                    option(
                        NSLocalizedString("Export Critical Event Logs", comment: "Report a problem option: export the critical event logs"),
                        detail: NSLocalizedString("Detailed logs as files. Only needed when a developer asks for them.", comment: "Report a problem option detail: export the critical event logs")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Report a Problem", comment: "Title of the report a problem screen"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reportFile, onDismiss: removeReportFile) { file in
            ActivityViewController(activityItems: [file.url])
        }
    }

    private func option(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundColor(.primary)
            Text(detail)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func shareDiagnosticReport(_ generate: @escaping () async -> String) {
        isPreparingReport = true
        Task { @MainActor in
            let date = Date()
            let report = "Generated: \(date)\n\n" + (await generate())
            let name = "Loop Report \(ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withSpaceBetweenDateAndTime, .withInternetDateTime])).md"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name.replacingOccurrences(of: ":", with: "-"))
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                writtenReportURL = url
                reportFile = ReportFile(url: url)
            } catch {
                reportFile = nil
            }
            isPreparingReport = false
        }
    }

    private func removeReportFile() {
        if let url = writtenReportURL {
            try? FileManager.default.removeItem(at: url)
        }
        writtenReportURL = nil
    }
}
