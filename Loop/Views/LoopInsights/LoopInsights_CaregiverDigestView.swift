//
//  LoopInsights_CaregiverDigestView.swift
//  Loop
//
//  LoopInsights — Caregiver / Family Digest configuration and manual send.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import MessageUI

struct LoopInsights_CaregiverDigestView: View {

    var dataStoresProvider: (() -> Any?)?

    @StateObject private var digestService = LoopInsights_CaregiverDigestService()
    @State private var coordinator: LoopInsights_Coordinator?

    @State private var isEnabled = LoopInsights_CaregiverDigestService.isEnabled
    @State private var frequency = LoopInsights_CaregiverDigestService.frequency
    @State private var deliveryMethod = LoopInsights_CaregiverDigestService.deliveryMethod
    @State private var recipientName = LoopInsights_CaregiverDigestService.recipientName
    @State private var recipientContact = LoopInsights_CaregiverDigestService.recipientContact
    @State private var showingMailCompose = false
    @State private var showingMessageCompose = false
    @State private var errorMessage: String?
    @State private var showingPreview = false

    private let tealColor = Color(red: 26/255, green: 138/255, blue: 158/255)

    var body: some View {
        List {
            headerSection
            configSection

            if isEnabled {
                recipientSection
                previewSection
                sendSection
                lastSentSection
            }

            infoSection

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Caregiver Digest", comment: "Caregiver digest nav title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMailCompose, onDismiss: {
            digestService.isGenerating = false
        }) {
            if let digest = digestService.lastGeneratedDigest {
                LoopInsights_MailComposeView(
                    recipients: recipientContact.isEmpty ? [] : [recipientContact],
                    subject: digest.subject,
                    htmlBody: digest.htmlBody
                ) { result in
                    if case .sent = result {
                        digestService.markSent()
                    }
                }
            }
        }
        .sheet(isPresented: $showingMessageCompose, onDismiss: {
            digestService.isGenerating = false
        }) {
            if let digest = digestService.lastGeneratedDigest {
                LoopInsights_MessageComposeView(
                    recipients: recipientContact.isEmpty ? [] : [recipientContact],
                    body: digest.plainText
                ) { result in
                    if case .sent = result {
                        digestService.markSent()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let digest = digestService.lastGeneratedDigest {
                NavigationView {
                    LoopInsights_DigestPreviewView(digest: digest)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button(NSLocalizedString("Done", comment: "Done button")) {
                                    showingPreview = false
                                }
                            }
                        }
                }
            }
        }
        .onAppear { initializeCoordinator() }
    }

    private func initializeCoordinator() {
        guard coordinator == nil else { return }
        if let testCoordinator = LoopInsights_Coordinator.withTestDataIfAvailable() {
            coordinator = testCoordinator
        } else if let any = dataStoresProvider?(),
                  let stores = any as? (GlucoseStoreProtocol, DoseStoreProtocol, CarbStoreProtocol, LatestStoredSettingsProvider, DisplayGlucosePreference, LoopInsightsSettingsWriter) {
            coordinator = LoopInsights_Coordinator(
                glucoseStore: stores.0,
                doseStore: stores.1,
                carbStore: stores.2,
                settingsProvider: stores.3,
                displayGlucosePreference: stores.4,
                settingsWriter: stores.5
            )
        } else {
            coordinator = LoopInsights_Coordinator(testDataProvider: LoopInsights_TestDataProvider())
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.title2)
                        .foregroundColor(tealColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Caregiver / Family Digest", comment: "Caregiver digest header"))
                            .font(.headline)
                        Text(NSLocalizedString("Share glucose summaries with family", comment: "Caregiver digest subtitle"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Configuration

    private var configSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.badge")
                        .foregroundColor(tealColor)
                    Text(NSLocalizedString("Enable Digest", comment: "Caregiver digest enable toggle"))
                }
            }
            .onChange(of: isEnabled) { newValue in
                LoopInsights_CaregiverDigestService.isEnabled = newValue
            }

            if isEnabled {
                Picker(selection: $frequency) {
                    ForEach(LoopInsights_CaregiverDigestService.DigestFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(tealColor)
                        Text(NSLocalizedString("Frequency", comment: "Caregiver digest frequency picker"))
                    }
                }
                .onChange(of: frequency) { newValue in
                    LoopInsights_CaregiverDigestService.frequency = newValue
                }

                Picker(selection: $deliveryMethod) {
                    ForEach(LoopInsights_CaregiverDigestService.DeliveryMethod.allCases) { method in
                        Label(method.displayName, systemImage: method.iconName).tag(method)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane")
                            .foregroundColor(tealColor)
                        Text(NSLocalizedString("Send Via", comment: "Caregiver digest delivery method picker"))
                    }
                }
                .onChange(of: deliveryMethod) { newValue in
                    LoopInsights_CaregiverDigestService.deliveryMethod = newValue
                }
            }
        } footer: {
            if isEnabled {
                Text(deliveryMethod == .email
                    ? NSLocalizedString("Digest will open a pre-filled email — just tap Send.", comment: "Caregiver digest email footer")
                    : NSLocalizedString("Digest will open a pre-filled iMessage — just tap Send.", comment: "Caregiver digest iMessage footer"))
            }
        }
    }

    // MARK: - Recipient

    private var recipientSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: deliveryMethod == .email ? "envelope" : "phone")
                    .foregroundColor(tealColor)
                TextField(
                    deliveryMethod == .email
                        ? NSLocalizedString("Recipient email address", comment: "Caregiver digest email placeholder")
                        : NSLocalizedString("Recipient phone number", comment: "Caregiver digest phone placeholder"),
                    text: $recipientContact
                )
                .keyboardType(deliveryMethod == .email ? .emailAddress : .phonePad)
                .textContentType(deliveryMethod == .email ? .emailAddress : .telephoneNumber)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: recipientContact) { newValue in
                    LoopInsights_CaregiverDigestService.recipientContact = newValue
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(tealColor)
                TextField(
                    NSLocalizedString("Recipient name (optional)", comment: "Caregiver digest recipient name placeholder"),
                    text: $recipientName
                )
                .onChange(of: recipientName) { newValue in
                    LoopInsights_CaregiverDigestService.recipientName = newValue
                }
            }
        } footer: {
            Text(deliveryMethod == .email
                ? NSLocalizedString("The email address will be pre-filled when you tap Send Now. Name personalizes the greeting (e.g. \"Hi Mom\").", comment: "Caregiver digest email recipient footer")
                : NSLocalizedString("The phone number will be pre-filled when you tap Send Now. Name personalizes the greeting (e.g. \"Hi Mom\").", comment: "Caregiver digest phone recipient footer"))
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            Button {
                generateAndPreview()
            } label: {
                HStack {
                    Image(systemName: "eye")
                        .foregroundColor(tealColor)
                    Text(NSLocalizedString("Preview Digest", comment: "Caregiver digest preview button"))
                        .foregroundColor(.primary)
                    Spacer()
                    if digestService.isGenerating && !showingMailCompose && !showingMessageCompose {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(digestService.isGenerating)
        }
    }

    // MARK: - Send Now

    private var sendSection: some View {
        Section {
            Button {
                generateAndSend()
            } label: {
                HStack {
                    Spacer()
                    if digestService.isGenerating && !showingPreview {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(NSLocalizedString("Generating...", comment: "Caregiver digest generating"))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: deliveryMethod.iconName)
                        Text(NSLocalizedString("Send Now", comment: "Caregiver digest send now button"))
                    }
                    Spacer()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 8)
            }
            .listRowBackground(digestService.isGenerating ? Color.gray : tealColor)
            .disabled(digestService.isGenerating)
        } footer: {
            if recipientContact.isEmpty {
                Text(NSLocalizedString("Add a recipient above so the message is pre-filled and ready to send.", comment: "Caregiver digest no recipient warning"))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Last Sent

    private var lastSentSection: some View {
        Section {
            if let lastSent = LoopInsights_CaregiverDigestService.lastSentDate {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Last Sent", comment: "Caregiver digest last sent label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lastSent, style: .relative)
                            .font(.subheadline)
                        + Text(NSLocalizedString(" ago", comment: "Caregiver digest time ago suffix"))
                            .font(.subheadline)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("No digest sent yet", comment: "Caregiver digest never sent"))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(NSLocalizedString("How it works", comment: "Caregiver digest info title"))
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(tealColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    infoRow(icon: "1.circle.fill", text: NSLocalizedString("Configure your recipient's email or phone above", comment: "Caregiver digest step 1"))
                    infoRow(icon: "2.circle.fill", text: NSLocalizedString("Tap \"Send Now\" — the message is pre-filled", comment: "Caregiver digest step 2"))
                    infoRow(icon: "3.circle.fill", text: NSLocalizedString("Just tap Send — no composing needed", comment: "Caregiver digest step 3"))
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Text(NSLocalizedString("The digest includes Time in Range, average glucose, insulin delivery, and meal data. No raw glucose readings or personal health details beyond the summary are shared.", comment: "Caregiver digest privacy note"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(tealColor)
                .font(.caption2)
            Text(text)
        }
    }

    // MARK: - Actions

    private func generateAndSend() {
        guard let coordinator = coordinator else {
            errorMessage = NSLocalizedString("Data not ready. Please try again.", comment: "Caregiver digest not ready")
            return
        }

        // Check availability before generating
        if deliveryMethod == .email && !MFMailComposeViewController.canSendMail() {
            errorMessage = NSLocalizedString("Mail is not configured on this device. Add a mail account in Settings or switch to iMessage.", comment: "Caregiver digest no mail")
            return
        }
        if deliveryMethod == .iMessage && !MFMessageComposeViewController.canSendText() {
            errorMessage = NSLocalizedString("iMessage/SMS is not available on this device. Switch to Email.", comment: "Caregiver digest no iMessage")
            return
        }

        errorMessage = nil
        Task {
            if let _ = await digestService.generateDigest(
                using: coordinator.dataAggregator,
                frequency: frequency,
                unitContext: coordinator.unitContext
            ) {
                await MainActor.run {
                    switch deliveryMethod {
                    case .email:
                        showingMailCompose = true
                    case .iMessage:
                        showingMessageCompose = true
                    }
                }
            } else {
                await MainActor.run {
                    errorMessage = NSLocalizedString("Failed to generate digest. Please try again.", comment: "Caregiver digest error")
                }
            }
        }
    }

    private func generateAndPreview() {
        guard let coordinator = coordinator else {
            errorMessage = NSLocalizedString("Data not ready. Please try again.", comment: "Caregiver digest not ready")
            return
        }
        errorMessage = nil
        Task {
            if let _ = await digestService.generateDigest(
                using: coordinator.dataAggregator,
                frequency: frequency,
                unitContext: coordinator.unitContext
            ) {
                await MainActor.run {
                    showingPreview = true
                }
            } else {
                await MainActor.run {
                    errorMessage = NSLocalizedString("Failed to generate digest. Please try again.", comment: "Caregiver digest error")
                }
            }
        }
    }
}

// MARK: - Digest Preview

struct LoopInsights_DigestPreviewView: View {
    let digest: LoopInsights_CaregiverDigestService.DigestContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Subject", comment: "Digest preview subject label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(digest.subject)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal)
                .padding(.top)

                Divider()

                Text(digest.plainText)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal)
            }
        }
        .navigationTitle(NSLocalizedString("Digest Preview", comment: "Digest preview title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Mail Compose (UIViewControllerRepresentable)

struct LoopInsights_MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let htmlBody: String
    let onResult: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(htmlBody, isHTML: true)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onResult: (MFMailComposeResult) -> Void
        init(onResult: @escaping (MFMailComposeResult) -> Void) { self.onResult = onResult }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onResult(result)
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Message Compose (UIViewControllerRepresentable)

struct LoopInsights_MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onResult: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = recipients
        vc.body = body
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onResult: (MessageComposeResult) -> Void
        init(onResult: @escaping (MessageComposeResult) -> Void) { self.onResult = onResult }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onResult(result)
            controller.dismiss(animated: true)
        }
    }
}
