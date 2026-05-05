//
//  DataLayer_ConsentView.swift
//  Loop
//
//  DataLayer — Unified consent UI for data sharing and research contribution.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Opt-in consent view for the DataLayer health data sharing platform.
/// Presented from LoopInsights settings. Covers provider sharing AND optional
/// research contribution with granular per-category toggles.
struct DataLayer_ConsentView: View {

    @ObservedObject private var consentManager = DataLayer_ConsentManager.shared
    @State private var isEnabled = DataLayer_FeatureFlags.isEnabled
    @State private var researchEnabled = DataLayer_FeatureFlags.researchEnabled
    @State private var showDeleteConfirmation = false
    @State private var selectedShareDays = 14
    @State private var isGeneratingShare = false
    @State private var shareError: String?
    @State private var justCopiedToken: String?
    @State private var selectedShareMethod = 0      // 0=PDF, 1=Provider, 2=Link
    @State private var selectedPDFDays = 14
    @State private var isGeneratingPDF = false
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?
    @State private var ingestEndpoint = DataLayer_FeatureFlags.ingestEndpointURL?.absoluteString ?? ""
    @State private var shareEndpoint = DataLayer_FeatureFlags.shareEndpointURL?.absoluteString ?? ""

    var body: some View {
        Form {
            masterToggleSection
            if isEnabled {
                disclosureSection
                categoryTogglesSection
                researchSection
                providerSharingSection
                dashboardSection
                configurationSection
                statsSection
                deleteSection
            }
        }
        .navigationTitle(NSLocalizedString("Data Sharing", comment: "DataLayer consent view title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isEnabled = DataLayer_FeatureFlags.isEnabled
            researchEnabled = DataLayer_FeatureFlags.researchEnabled
        }
        .alert(
            NSLocalizedString("Delete All Data", comment: "DataLayer delete alert title"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(NSLocalizedString("Delete Everything", comment: "DataLayer delete button"), role: .destructive) {
                DataLayer_Coordinator.shared.deleteAllData()
                isEnabled = false
                researchEnabled = false
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("This will permanently delete all collected data from this device, revoke all consent, and disable Data Sharing. This cannot be undone.", comment: "DataLayer delete warning"))
        }
    }

    // MARK: - Master Toggle

    private var masterToggleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("DATA SHARING", comment: "DataLayer header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Toggle(NSLocalizedString("Enable Data Sharing", comment: "DataLayer master toggle"), isOn: $isEnabled)
                    .onChange(of: isEnabled) { newValue in
                        DataLayer_FeatureFlags.isEnabled = newValue
                        if newValue {
                            DataLayer_Coordinator.shared.start()
                        } else {
                            DataLayer_Coordinator.shared.stop()
                        }
                    }

                Text(NSLocalizedString("Control how your diabetes data is shared. All sharing is off by default and requires your explicit consent for each data category.", comment: "DataLayer master toggle description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Disclosure

    private var disclosureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("How Your Data Is Used", comment: "DataLayer disclosure header"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text(NSLocalizedString("Your data can be used in two ways: (1) shared directly with a healthcare provider you choose, and (2) combined with other users' anonymized data to improve diabetes care and support research. You control which data categories are shared.", comment: "DataLayer disclosure text"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Category Toggles

    private var categoryTogglesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("DATA CATEGORIES", comment: "DataLayer categories header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Text(NSLocalizedString("Choose which types of data you want to share. Each category can be enabled or disabled independently.", comment: "DataLayer categories description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(DataLayer_ConsentCategory.allCases) { category in
                    categoryToggle(for: category)
                    if category != DataLayer_ConsentCategory.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private func categoryToggle(for category: DataLayer_ConsentCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { consentManager.isGranted(for: category) },
                set: { consentManager.setConsent(for: category, granted: $0) }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: category.iconName)
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text(category.displayName)
                }
            }
            Text(category.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 28)
        }
    }

    // MARK: - Research Toggle

    private var researchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundColor(.purple)
                    Text(NSLocalizedString("RESEARCH CONTRIBUTION", comment: "DataLayer research header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Toggle(NSLocalizedString("Contribute to Diabetes Research", comment: "DataLayer research toggle"), isOn: $researchEnabled)
                    .onChange(of: researchEnabled) { newValue in
                        DataLayer_FeatureFlags.researchEnabled = newValue
                    }

                Text(NSLocalizedString("When enabled, your consented data categories are anonymized and uploaded to support diabetes research. Your identity is never shared — data is stripped of personal identifiers, timestamps are generalized, and statistical noise is added for privacy.", comment: "DataLayer research description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !consentManager.hasAnyConsent && researchEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("Enable at least one data category above to contribute data.", comment: "DataLayer no categories warning"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Provider Sharing

    private var providerSharingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .foregroundColor(.green)
                    Text(NSLocalizedString("SHARE WITH PROVIDER", comment: "DataLayer provider header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Picker("", selection: $selectedShareMethod) {
                    Text("PDF Report").tag(0)
                    Text("Provider Portal").tag(1)
                    Text("Share Link").tag(2)
                }
                .pickerStyle(.segmented)

                switch selectedShareMethod {
                case 0:
                    pdfReportTab
                case 1:
                    providerPortalTab
                default:
                    shareLinkTab
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL {
                LoopInsights_ActivityViewRepresentable(activityItems: [url])
            }
        }
    }

    // MARK: - PDF Report Tab

    private var pdfReportTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Generate a downloadable report. Share via email, AirDrop, or print.", comment: "DataLayer PDF description"))
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Time Range", comment: "DataLayer PDF time range"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedPDFDays) {
                    Text("3d").tag(3)
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                    Text("30d").tag(30)
                    Text("90d").tag(90)
                }
                .pickerStyle(.segmented)
            }

            let consentedLabels = consentedCategoryLabels
            if !consentedLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Included: \(consentedLabels)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                generatePDFReport()
            } label: {
                HStack {
                    if isGeneratingPDF {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.richtext")
                    }
                    Text(isGeneratingPDF
                         ? NSLocalizedString("Generating...", comment: "DataLayer PDF generating")
                         : NSLocalizedString("Generate PDF Report", comment: "DataLayer PDF button"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isGeneratingPDF || !consentManager.hasAnyConsent)

            if let error = shareError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Provider Portal Tab

    private var providerPortalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if DataLayer_ProviderRegistry.shared.hasProviders {
                ForEach(0..<DataLayer_ProviderRegistry.shared.providers.count, id: \.self) { index in
                    let provider = DataLayer_ProviderRegistry.shared.providers[index]
                    HStack(spacing: 10) {
                        Image(systemName: provider.iconName)
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.subheadline)
                            Text(provider.isConfigured
                                 ? NSLocalizedString("Connected", comment: "DataLayer provider connected")
                                 : NSLocalizedString("Not configured", comment: "DataLayer provider not configured"))
                                .font(.caption)
                                .foregroundColor(provider.isConfigured ? .green : .secondary)
                        }
                        Spacer()
                        if !provider.isConfigured {
                            Button(NSLocalizedString("Setup", comment: "DataLayer provider setup")) {}
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "building.2.crop.circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Digital Provider Integration", comment: "DataLayer portal title"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(NSLocalizedString("Direct uploads to healthcare provider portals coming soon. Use PDF Report or Share Link in the meantime.", comment: "DataLayer portal coming soon"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Share Link Tab

    private var shareLinkTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Generate a time-scoped link to share your data with a healthcare provider. They'll see a read-only dashboard with your glucose, insulin, meals, and other enabled categories.", comment: "DataLayer provider description"))
                .font(.caption)
                .foregroundColor(.secondary)

            if DataLayer_FeatureFlags.shareEndpointURL != nil {
                Picker(NSLocalizedString("Time Range", comment: "DataLayer share time range"), selection: $selectedShareDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                Button {
                    generateShare()
                } label: {
                    HStack {
                        if isGeneratingShare {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "link.badge.plus")
                        }
                        Text(isGeneratingShare
                             ? NSLocalizedString("Generating...", comment: "DataLayer share generating")
                             : NSLocalizedString("Generate Share Link", comment: "DataLayer share button"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isGeneratingShare || !consentManager.hasAnyConsent)

                if let error = shareError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                let activeLinks = DataLayer_FeatureFlags.activeShares.filter { !$0.isExpired }
                if !activeLinks.isEmpty {
                    Divider()
                    Text(NSLocalizedString("Active Share Links", comment: "DataLayer active shares header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(activeLinks) { link in
                        shareLinkRow(link)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("Share links require a share endpoint to be configured.", comment: "DataLayer share not configured"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    private func shareLinkRow(_ link: DataLayer_ShareLink) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(link.daysCovered)-day report")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(link.categoryCount) categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(link.expiresAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = link.url
                    justCopiedToken = link.token
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if justCopiedToken == link.token { justCopiedToken = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: justCopiedToken == link.token ? "checkmark" : "doc.on.doc")
                        Text(justCopiedToken == link.token
                             ? NSLocalizedString("Copied", comment: "DataLayer link copied")
                             : NSLocalizedString("Copy Link", comment: "DataLayer copy link"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button(role: .destructive) {
                    DataLayer_Coordinator.shared.revokeShareLink(token: link.token) { _ in
                        DispatchQueue.main.async {
                            // Triggers re-render since activeShares changed
                            shareError = nil
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(NSLocalizedString("Revoke", comment: "DataLayer revoke link"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var consentedCategoryLabels: String {
        let labels = DataLayer_ConsentCategory.allCases
            .filter { consentManager.isGranted(for: $0) }
            .map { $0.displayName }
        return labels.joined(separator: ", ")
    }

    private func generatePDFReport() {
        isGeneratingPDF = true
        shareError = nil

        Task {
            if let url = await DataLayer_ReportGenerator.generateReport(days: selectedPDFDays) {
                await MainActor.run {
                    pdfURL = url
                    isGeneratingPDF = false
                    showingShareSheet = true
                }
            } else {
                await MainActor.run {
                    isGeneratingPDF = false
                    shareError = NSLocalizedString("Failed to generate PDF report.", comment: "DataLayer PDF error")
                }
            }
        }
    }

    private func generateShare() {
        isGeneratingShare = true
        shareError = nil

        DataLayer_Coordinator.shared.generateShareLink(days: selectedShareDays) { result in
            DispatchQueue.main.async {
                isGeneratingShare = false
                switch result {
                case .success(let link):
                    UIPasteboard.general.string = link.url
                    justCopiedToken = link.token
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if justCopiedToken == link.token { justCopiedToken = nil }
                    }
                case .failure(let error):
                    shareError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Dashboard Link

    private var dashboardSection: some View {
        Section {
            NavigationLink(destination: DataLayer_DashboardView()) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Data Dashboard", comment: "DataLayer dashboard link"))
                            .font(.subheadline)
                        Text(NSLocalizedString("View recorded events, trends, and upload status", comment: "DataLayer dashboard description"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("BACKEND CONFIGURATION", comment: "DataLayer config header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                Text(NSLocalizedString("These settings connect to the cloud backend that powers Research Contribution uploads and Share Link generation. They are not related to PDF Reports or the Provider Portal.", comment: "DataLayer config description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ingest Endpoint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("https://...", text: $ingestEndpoint)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: ingestEndpoint) { newValue in
                            DataLayer_FeatureFlags.ingestEndpointURL = newValue.isEmpty ? nil : URL(string: newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Share Endpoint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("https://...", text: $shareEndpoint)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: shareEndpoint) { newValue in
                            DataLayer_FeatureFlags.shareEndpointURL = newValue.isEmpty ? nil : URL(string: newValue)
                        }
                }

                if !ingestEndpoint.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("Endpoint configured — uploads will sync every 15 minutes", comment: "DataLayer config ready"))
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("LOCAL DATA", comment: "DataLayer stats header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                HStack {
                    Text(NSLocalizedString("Events Collected", comment: "DataLayer events count label"))
                    Spacer()
                    Text("\(DataLayer_Coordinator.shared.totalEventCount)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(NSLocalizedString("Categories Enabled", comment: "DataLayer categories count label"))
                    Spacer()
                    Text("\(consentManager.grantedCount) of \(DataLayer_ConsentCategory.allCases.count)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(NSLocalizedString("Retention Period", comment: "DataLayer retention label"))
                    Spacer()
                    Text("\(DataLayer_FeatureFlags.retentionDays) days")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Delete All

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text(NSLocalizedString("Delete All My Data", comment: "DataLayer delete button"))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Text(NSLocalizedString("Permanently deletes all collected data from this device, revokes all consent, and disables Data Sharing.", comment: "DataLayer delete description - this will not disable use of other LoopInsights features."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
