//
//  ShareOutcomesView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct ShareOutcomesView: View {
    @StateObject private var viewModel: ShareOutcomesViewModel
    @State private var pendingDeletion: OutcomesShareReceipt?

    static let policyURL = URL(string: "https://analytics.loopkit.org/policy")!

    init(viewModel: @autoclosure @escaping () -> ShareOutcomesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            Section(footer: Text(NSLocalizedString("Loop developers use shared outcomes to learn how settings changes and algorithm experiments affect time in range and lows. Each share is sent only when you tap Send.", comment: "Footer of the introduction on the share outcomes screen"))) {
                Text(String(format: NSLocalizedString("Send the Loop developers your history from %1$@, covering your current setup and the weeks before it.", comment: "Introduction on the share outcomes screen (1: date range)"),
                            dateIntervalFormatter.string(from: viewModel.range) ?? ""))
            }
            Section(header: SectionHeader(label: NSLocalizedString("What's Sent", comment: "Header of the list of what an outcomes share includes"))) {
                item(NSLocalizedString("Glucose readings", comment: "Outcomes share content item"))
                item(NSLocalizedString("Carb entries, without food descriptions", comment: "Outcomes share content item"))
                item(NSLocalizedString("Insulin delivery", comment: "Outcomes share content item"))
                item(NSLocalizedString("Loop's dosing decisions and forecasts", comment: "Outcomes share content item"))
                item(NSLocalizedString("Therapy settings history, including algorithm experiments", comment: "Outcomes share content item"))
                item(NSLocalizedString("Preset history, including preset names", comment: "Outcomes share content item"))
                item(NSLocalizedString("Pump and CGM models, app version and build", comment: "Outcomes share content item"))
                item(NSLocalizedString("A random ID for this app, so shares from it can be linked", comment: "Outcomes share content item"))
                item(NSLocalizedString("Your note, if you add one", comment: "Outcomes share content item"))
            }
            Section(header: SectionHeader(label: NSLocalizedString("What's Not Sent", comment: "Header of the list of what an outcomes share leaves out"))) {
                item(NSLocalizedString("Your name or contact details", comment: "Outcomes share exclusion item"))
                item(NSLocalizedString("Phone name, and pump and CGM serial numbers", comment: "Outcomes share exclusion item"))
                item(NSLocalizedString("Device communication logs and alerts", comment: "Outcomes share exclusion item"))
            }
            Section {
                Link(NSLocalizedString("Data Policy", comment: "Link to the shared outcomes data policy"), destination: Self.policyURL)
            }
            if viewModel.canEditNote {
                noteSection
            }
            sendSection
            if !viewModel.receipts.isEmpty {
                receiptsSection
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(NSLocalizedString("Share Outcomes", comment: "Title of the share outcomes screen"))
        .task { await viewModel.prepare() }
        .onDisappear { viewModel.cancel() }
        .confirmationDialog(NSLocalizedString("Delete this share from the LoopKit server?", comment: "Confirmation title for deleting an outcomes share"),
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { receipt in
            Button(NSLocalizedString("Delete Share", comment: "Button to delete an outcomes share"), role: .destructive) {
                Task { await viewModel.delete(receipt) }
            }
        }
    }

    private var noteSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Note", comment: "Header of the optional note sent with an outcomes share")),
                footer: Text(String(format: NSLocalizedString("Optional. Anything that would help the developers understand these results, such as illness, travel or a change in routine. Don't include your name or contact details. %1$d of %2$d characters.", comment: "Footer for the note sent with an outcomes share (1: used)(2: limit)"), viewModel.note.count, ShareOutcomesViewModel.maxNoteLength))) {
            TextField(NSLocalizedString("Add a note", comment: "Placeholder for the note sent with an outcomes share"), text: $viewModel.note, axis: .vertical)
                .lineLimit(3...8)
                .onChange(of: viewModel.note) { _, note in
                    if note.count > ShareOutcomesViewModel.maxNoteLength {
                        viewModel.note = String(note.prefix(ShareOutcomesViewModel.maxNoteLength))
                    }
                }
        }
    }

    @ViewBuilder
    private var sendSection: some View {
        Section(footer: sendFooter) {
            switch viewModel.state {
            case .preparing(let fraction):
                ProgressView(value: fraction) {
                    Text(NSLocalizedString("Preparing…", comment: "Shown while the outcomes share is being prepared"))
                }
            case .ready(let package):
                summaryRows(package)
                Button(NSLocalizedString("Send", comment: "Button to send an outcomes share")) {
                    Task { await viewModel.send() }
                }
            case .sending(let package):
                summaryRows(package)
                HStack {
                    Text(NSLocalizedString("Sending…", comment: "Shown while the outcomes share is uploading"))
                    Spacer()
                    ProgressView()
                }
            case .sent(let receipt):
                Label(NSLocalizedString("Sent. Thank you!", comment: "Shown after an outcomes share is sent"), systemImage: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                LabeledContent(NSLocalizedString("Receipt", comment: "Label for an outcomes share's receipt ID"), value: receipt.id)
                    .textSelection(.enabled)
            case .deleted:
                Text(NSLocalizedString("The share was deleted.", comment: "Shown after the outcomes share just sent is deleted"))
            case .failed(let message, let package):
                Text(message)
                    .foregroundColor(.red)
                if package != nil {
                    Button(NSLocalizedString("Try Again", comment: "Button to retry sending an outcomes share")) {
                        Task { await viewModel.send() }
                    }
                }
            }
        }
    }

    private var sendFooter: some View {
        var text = NSLocalizedString("Shares are stored on a LoopKit server that only Loop developers can access. You can delete a share from this screen at any time.", comment: "Footer explaining how outcomes shares are stored")
        if case .ready = viewModel.state, let previous = viewModel.previousShare {
            text = String(format: NSLocalizedString("You shared this setup on %@.", comment: "Note that the current setup was already shared (1: date)"), previous.sent.formatted(date: .abbreviated, time: .shortened)) + " " + text
        }
        return Text(text)
    }

    @ViewBuilder
    private func summaryRows(_ package: OutcomesPackage) -> some View {
        LabeledContent(NSLocalizedString("Size", comment: "Label for the size of an outcomes share"), value: ByteCountFormatter.string(fromByteCount: package.bytes, countStyle: .file))
    }

    private var receiptsSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Your Shares", comment: "Header of the list of outcomes shares sent from this app")),
                footer: viewModel.deletionError.map { Text($0).foregroundColor(.red) }) {
            ForEach(viewModel.receipts.reversed()) { receipt in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(receipt.sent.formatted(date: .abbreviated, time: .shortened))
                        Text(receipt.id)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(NSLocalizedString("Delete", comment: "Button to delete an outcomes share"), role: .destructive) {
                        pendingDeletion = receipt
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var dateIntervalFormatter: DateIntervalFormatter {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private func item(_ text: String) -> some View {
        Text(text)
    }
}
