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

    var body: some View {
        Form {
            masterToggleSection
            if isEnabled {
                disclosureSection
                categoryTogglesSection
                researchSection
                providerSharingSection
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

    // MARK: - Provider Sharing (placeholder for Phase 5)

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

                Text(NSLocalizedString("Generate a time-scoped link to share your data with a healthcare provider. They'll see a read-only dashboard with your glucose, insulin, meals, and other enabled categories.", comment: "DataLayer provider description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("Coming soon — provider sharing will be available in a future update.", comment: "DataLayer provider coming soon"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
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

            Text(NSLocalizedString("Permanently deletes all collected data from this device, revokes all consent, and disables Data Sharing.", comment: "DataLayer delete description"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
