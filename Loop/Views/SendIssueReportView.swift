//
//  SendIssueReportView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import PhotosUI
import SwiftUI

struct SendIssueReportView: View {
    let context: [String: IssueReportContextValue]
    let generateDiagnosticReport: (() async -> String)?
    let exportLocally: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var isAnonymous = true
    @State private var contact = IssueReport.Contact()
    @State private var includeDiagnosticReport = true
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var screenshots: [Screenshot] = []
    @State private var isSending = false
    @State private var sentReportID: String?
    @State private var sendError: IssueReportSubmitterError?
    @State private var showingError = false

    private static let maxDescriptionLength = 20_000
    private static let maxScreenshots = 8
    private static let maxAttachmentBytes = 10_000_000

    private struct Screenshot: Identifiable {
        let id = UUID()
        let image: UIImage
        let attachment: IssueReport.Attachment
    }

    var body: some View {
        Form {
            Section(footer: Text(String(format: NSLocalizedString("%1$d of %2$d characters", comment: "Issue report description length (1: used)(2: limit)"), description.count, Self.maxDescriptionLength))) {
                TextField(NSLocalizedString("Title (optional)", comment: "Placeholder for the issue report title"), text: $title)
                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text(NSLocalizedString("Describe what you saw and what you expected to happen", comment: "Placeholder for the issue report description"))
                            .foregroundColor(Color(.placeholderText))
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $description)
                        .frame(minHeight: 160)
                }
            }

            screenshotsSection

            Section(footer: Text(isAnonymous ?
                NSLocalizedString("The report won't include your name, contact details or anything else that identifies you.", comment: "Footer for an anonymous issue report") :
                NSLocalizedString("Fill in any of these so developers can follow up with you.", comment: "Footer for issue report contact details"))
            ) {
                Toggle(NSLocalizedString("Submit Anonymously", comment: "Toggle for submitting an issue report without contact details"), isOn: $isAnonymous)
                if !isAnonymous {
                    TextField(NSLocalizedString("Name", comment: "Issue report contact name placeholder"), text: binding(\.name))
                        .textContentType(.name)
                    TextField(NSLocalizedString("Email", comment: "Issue report contact email placeholder"), text: binding(\.email))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField(NSLocalizedString("Zulip Name", comment: "Issue report contact Zulip placeholder"), text: binding(\.zulip))
                        .textInputAutocapitalization(.never)
                    TextField(NSLocalizedString("GitHub Username", comment: "Issue report contact GitHub placeholder"), text: binding(\.github))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if generateDiagnosticReport != nil {
                Section(footer: Text(NSLocalizedString("Attaches Loop's issue report as a text file. It contains health data such as recent glucose, insulin, carbs and your therapy settings.", comment: "Footer for the include diagnostic report toggle"))) {
                    Toggle(NSLocalizedString("Include Diagnostic Report", comment: "Toggle for attaching the diagnostic report to an issue report"), isOn: $includeDiagnosticReport)
                }
            }

            Section(header: Text(NSLocalizedString("Also Sent", comment: "Header for the build and device details sent with an issue report")),
                    footer: Text(NSLocalizedString("Reports go to the LoopKit development team and are visible only to them. Your IP address is used only to limit how often reports can be sent and is never stored.", comment: "Privacy footer for issue reports")))
            {
                ForEach(context.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(Self.displayValue(context[key]))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.footnote)
                }
            }

            Section(footer: Text(NSLocalizedString("Opens Loop's diagnostic report so you can save it or share it yourself. Nothing is sent to the developers.", comment: "Footer for exporting the issue report locally"))) {
                Button(NSLocalizedString("Export Locally Instead", comment: "Button to open the diagnostic report for local export instead of submitting"), action: exportLocally)
            }
        }
        .navigationTitle(NSLocalizedString("Report Issue", comment: "Title of the issue report screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button(NSLocalizedString("Submit", comment: "Button to submit an issue report to the developers")) {
                        send()
                    }
                    .disabled(!canSend)
                }
            }
        }
        .disabled(isSending)
        .onChange(of: photoSelection) { _, items in
            loadScreenshots(items)
        }
        .alert(NSLocalizedString("Report Submitted", comment: "Title of the alert after an issue report was submitted"), isPresented: Binding(get: { sentReportID != nil }, set: { if !$0 { sentReportID = nil } })) {
            Button(NSLocalizedString("Copy ID", comment: "Button to copy the issue report ID")) {
                UIPasteboard.general.string = sentReportID
                dismiss()
            }
            Button(NSLocalizedString("Done", comment: "Button to close the issue report sent alert"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(String(format: NSLocalizedString("Thank you. Your report ID is %1$@. Mention it if you discuss the problem on Zulip or GitHub.", comment: "Message after an issue report was sent (1: report ID)"), sentReportID ?? ""))
        }
        .alert(NSLocalizedString("Unable to Submit Report", comment: "Title of the alert when an issue report fails"), isPresented: $showingError, presenting: sendError) { error in
            if error.isRetryable {
                Button(NSLocalizedString("Try Again", comment: "Button to retry sending an issue report")) {
                    send()
                }
            }
            Button(NSLocalizedString("OK", comment: "Button to close the issue report error alert"), role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var screenshotsSection: some View {
        Section(footer: Text(String(format: NSLocalizedString("Up to %1$d screenshots or photos.", comment: "Footer for issue report screenshots (1: limit)"), Self.maxScreenshots))) {
            if !screenshots.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(screenshots) { screenshot in
                            Image(uiImage: screenshot.image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            PhotosPicker(selection: $photoSelection, maxSelectionCount: Self.maxScreenshots, matching: .images) {
                Text(screenshots.isEmpty ?
                    NSLocalizedString("Add Screenshots", comment: "Button to choose screenshots for an issue report") :
                    NSLocalizedString("Change Screenshots", comment: "Button to change the screenshots on an issue report"))
            }
        }
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedDescription.isEmpty && description.count <= Self.maxDescriptionLength
    }

    private func binding(_ keyPath: WritableKeyPath<IssueReport.Contact, String?>) -> Binding<String> {
        Binding(get: { contact[keyPath: keyPath] ?? "" }, set: { contact[keyPath: keyPath] = $0 })
    }

    private func loadScreenshots(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [Screenshot] = []
            for (index, item) in items.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self), let screenshot = Self.screenshot(from: data, index: index + 1) else {
                    continue
                }
                loaded.append(screenshot)
            }
            screenshots = loaded
        }
    }

    // The server accepts only PNG and JPEG, so anything else (HEIC from the camera) is converted
    private static func screenshot(from data: Data, index: Int) -> Screenshot? {
        guard let image = UIImage(data: data) else {
            return nil
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]), data.count <= maxAttachmentBytes {
            return Screenshot(image: image, attachment: .init(filename: "screenshot-\(index).png", contentType: "image/png", data: data))
        }
        for quality in [0.8, 0.5, 0.3] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= maxAttachmentBytes {
                return Screenshot(image: image, attachment: .init(filename: "screenshot-\(index).jpg", contentType: "image/jpeg", data: jpeg))
            }
        }
        return nil
    }

    private static func displayValue(_ value: IssueReportContextValue?) -> String {
        switch value {
        case .string(let string): return string
        case .strings(let strings): return strings.isEmpty ? "–" : strings.joined(separator: ", ")
        case nil: return ""
        }
    }

    private func send() {
        isSending = true
        Task {
            var attachments = screenshots.map(\.attachment)
            if includeDiagnosticReport, let generateDiagnosticReport {
                let report = await generateDiagnosticReport()
                // Stay under the server's per-file limit; decoding repairs a character cut in half
                let text = String(decoding: report.utf8.prefix(Self.maxAttachmentBytes - 4), as: UTF8.self)
                attachments.append(.init(filename: "diagnostic-report.txt", contentType: "text/plain; charset=utf-8", data: Data(text.utf8)))
            }
            let report = IssueReport(
                title: title.isEmpty ? nil : String(title.prefix(200)),
                description: trimmedDescription,
                contact: isAnonymous ? nil : Self.trimmed(contact),
                context: context,
                attachments: attachments
            )
            do {
                sentReportID = try await IssueReportSubmitter().submit(report)
            } catch let error as IssueReportSubmitterError {
                sendError = error
                showingError = true
            } catch {
                sendError = .network(error)
                showingError = true
            }
            isSending = false
        }
    }

    private static func trimmed(_ contact: IssueReport.Contact) -> IssueReport.Contact? {
        func clean(_ value: String?) -> String? {
            let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        let result = IssueReport.Contact(name: clean(contact.name), email: clean(contact.email), zulip: clean(contact.zulip), github: clean(contact.github))
        return [result.name, result.email, result.zulip, result.github].allSatisfy({ $0 == nil }) ? nil : result
    }
}
