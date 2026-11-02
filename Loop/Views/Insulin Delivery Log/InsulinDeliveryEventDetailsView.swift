//
//  InsulinDeliveryEventDetailsView.swift
//  Loop
//
//  Created by Cameron Ingham on 7/7/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI

struct InsulinDeliveryEventDetailsView: View {

    @Environment(\.dismiss) private var dismiss

    let basalUnitsFormatter = QuantityFormatter(for: .internationalUnitsPerHour)
    let bolusUnitsFormatter = QuantityFormatter(for: .internationalUnit)
    let durationFormatter = DateComponentsFormatter()

    let pumpEventType: InsulinDeliveryLogEvent.EventType.PumpEventType
    let doseEntry: DoseEntry
    let onTapGesture: (DoseEntry) -> Void
    let onDelete: ((DoseEntry) async -> Void)?

    @State private var showingDeleteConfirmation = false
    
    var doseTypeValue: String {
        if case .bolus(.external, _, _) = pumpEventType {
            return NSLocalizedString("External Insulin", comment: "Dose type label for a manually-entered bolus")
        }
        switch pumpEventType {
        case .basal(let basalEventType, _):
            switch basalEventType {
            case .automatedPresetBasal:
                return NSLocalizedString("Temp Basal", comment: "")
            case .automationOff:
                return NSLocalizedString("Scheduled Basal", comment: "")
            case .automationOn(basalStatus: let basalStatus):
                switch basalStatus {
                case .lessThanScheduled:
                    return NSLocalizedString("Temp Basal", comment: "")
                case .moreThanScheduled:
                    return NSLocalizedString("Temp Basal", comment: "")
                case .scheduled:
                    return NSLocalizedString("Scheduled Basal", comment: "")
                }
            case .manualTempBasal:
                return NSLocalizedString("Temp Basal", comment: "")
            }
        case .bolus:
            return NSLocalizedString("Bolus", comment: "")
        case .insulin(let insulinEventType):
            switch insulinEventType {
            case .resumed:
                return NSLocalizedString("Insulin Resumed", comment: "")
            case .suspended:
                return NSLocalizedString("Insulin Suspended", comment: "")
            }
        }
    }
    
    var startTimeValue: String? {
        doseEntry.startDate.formatted(date: .omitted, time: .standard)
    }

    var endTimeValue: String? {
        guard doseEntry.startDate != doseEntry.endDate, !doseEntry.isMutable else { return nil }
        return doseEntry.endDate.formatted(date: .omitted, time: .standard)
    }

    var durationValue: String? {
        durationFormatter.unitsStyle = .abbreviated
        
        return durationFormatter.string(from: doseEntry.duration)
    }
    
    var deliveredUnitsValue: String? {
        switch pumpEventType {
        case .basal(_, let rate):
            return basalUnitsFormatter.string(from: rate)
        case .bolus(_, _, let deliveryAmount):
            return bolusUnitsFormatter.string(from: deliveryAmount)
        case .insulin:
            return basalUnitsFormatter.string(from: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: 0))
        }
    }
    
    private var isExternalDose: Bool {
        doseEntry.manuallyEntered
    }

    private var isDeletableDoseType: Bool {
        switch pumpEventType {
        case .bolus, .basal:
            return true
        case .insulin:
            return false
        }
    }

    // External (manually-entered) doses can always be deleted; deleting any other
    // (Loop-recorded) dose is gated behind the doseDeletion feature flag. In-progress
    // (mutable) doses can never be deleted — you can't delete a dose still being delivered.
    private var showDeleteButton: Bool {
        onDelete != nil && isDeletableDoseType && !doseEntry.isMutable && (isExternalDose || FeatureFlags.doseDeletionEnabled)
    }

    /// True while the dose still contributes active insulin (within the ~6h insulin activity window).
    private var doseHasActiveInsulin: Bool {
        doseEntry.endDate > Date().addingTimeInterval(-.hours(6))
    }

    private var deleteButtonTitle: String {
        isExternalDose
            ? NSLocalizedString("Delete External Insulin", comment: "Button to delete a manually-entered insulin dose")
            : NSLocalizedString("Delete Dose", comment: "Button to delete a dose")
    }

    private var deleteConfirmationTitle: String {
        isExternalDose
            ? NSLocalizedString("Delete this manually-entered insulin entry?", comment: "Confirmation title for deleting a manually-entered insulin dose")
            : NSLocalizedString("Delete this dose?", comment: "Confirmation title for deleting a dose")
    }

    /// Extra warning shown when deleting a Loop-recorded dose that still has active insulin.
    private var deleteConfirmationMessage: String? {
        guard !isExternalDose, doseHasActiveInsulin else { return nil }
        return NSLocalizedString("This dose still has active insulin. Deleting it may cause Loop to make up for the reduced active insulin by dosing more.", comment: "Warning when deleting a Loop-recorded dose that still has active insulin")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading) {
                    Text("Dose Type")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(doseTypeValue)
                }
                
                if let startTimeValue {
                    VStack(alignment: .leading) {
                        Text("Start Time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text(startTimeValue)
                    }
                }

                if let endTimeValue {
                    VStack(alignment: .leading) {
                        Text("End Time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(endTimeValue)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Mutable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(doseEntry.isMutable ? "Yes" : "No")
                }

                switch pumpEventType {
                case .basal, .bolus:
                    if let durationValue {
                        VStack(alignment: .leading) {
                            Text("Duration")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(durationValue)
                        }
                    }
                    
                    if let deliveredUnitsValue {
                        VStack(alignment: .leading) {
                            Text("Insulin Delivery")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(deliveredUnitsValue)
                        }
                    }
                case .insulin:
                    EmptyView()
                }
            } header: {
                Text("Delivery Details")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTapGesture(doseEntry)
            }

            if showDeleteButton, let onDelete {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(deleteButtonTitle)
                            Spacer()
                        }
                    }
                }
                .confirmationDialog(
                    Text(deleteConfirmationTitle),
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await onDelete(doseEntry)
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    if let deleteConfirmationMessage {
                        Text(deleteConfirmationMessage)
                    }
                }
            }
        }
        .navigationTitle(Text("Insulin Event"))
    }
}
