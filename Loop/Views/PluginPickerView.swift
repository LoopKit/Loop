//
//  PluginPickerView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

/// A full-screen chooser for setting up a new CGM, pump, or service plugin,
/// showing an icon for each choice and grouping devices by manufacturer and
/// services by category.
///
/// The view never dismisses itself: the presenter reacts to `onSelect`/`onCancel`
/// so that setup UI can be presented only after the picker is fully dismissed.
struct PluginPickerView: View {
    enum PluginType: Hashable {
        case cgm
        case pump
        case service
        
        var localizedTitle: String {
            switch self {
            case .cgm:
                NSLocalizedString("Add CGM", comment: "The title of the CGM chooser in settings")
            case .pump:
                NSLocalizedString("Add Pump", comment: "The title of the pump chooser in settings")
            case .service:
                NSLocalizedString("Add Service", comment: "The title of the add service picker in settings")
            }
        }
        
        var fallbackSystemImage: String {
            switch self {
            case .cgm:
                "sensor.tag.radiowaves.forward"
            case .pump:
                "ivfluid.bag"
            case .service:
                "network"
            }
        }
    }
    
    struct Item: Identifiable {
        let id: String
        let title: String

        /// The section this item is listed under: the manufacturer for devices, the category for services
        let group: String?

        let image: UIImage?
    }

    let pluginType: PluginType
    let items: [Item]
    let onSelect: (Item) -> Void
    let onCancel: () -> Void

    private static let otherGroup = NSLocalizedString("Other", comment: "The group name for plugins that do not declare a manufacturer or category")

    /// Matches the group used by the static simulator descriptors (see availableStaticPumpManagers et al.)
    private static let simulatorGroup = "Simulator"
    
    /// Matches the group used by the remote device descriptors
    private static let remoteGroup = "Remote"

    private struct ItemGroup: Identifiable {
        let id: String
        let items: [Item]
    }

    private var groups: [ItemGroup] {
        Dictionary(grouping: items) { $0.group ?? Self.otherGroup }
            .map { name, items in
                ItemGroup(id: name, items: items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
            }
            .sorted { (rank(of: $0.id), $0.id) < (rank(of: $1.id), $1.id) }
    }

    /// Named groups sort alphabetically; Physical devices first, then remote devices, then simulators
    private func rank(of groupName: String) -> Int {
        switch groupName {
        case Self.otherGroup:
            return 3
        case Self.simulatorGroup:
            return 2
        case Self.remoteGroup:
            return 1
        default:
            return 0
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(groups) { group in
                    Section(header: SectionHeader(label: group.id)) {
                        rows(for: group)
                    }
                }
            }
            .insetGroupedListStyle()
            .navigationBarTitle(Text(pluginType.localizedTitle))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Cancel", comment: "The title of the cancel button in the plugin picker"), action: onCancel)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func rows(for group: ItemGroup) -> some View {
        ForEach(group.items) { item in
            Button(action: { onSelect(item) }) {
                HStack(spacing: 12) {
                    PluginIconView(image: item.image, fallbackSystemImage: pluginType.fallbackSystemImage)
                    Text(item.title)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pluginPickerItem-\(item.id)")
        }
    }
}

private struct PluginIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let image: UIImage?
    let fallbackSystemImage: String

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 21))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: 48, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
    }

    private var resolvedImage: UIImage? {
        guard let image else { return nil }
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        return image.imageAsset?.image(with: traits) ?? image
    }
}

extension PluginPickerView.Item {
    init(_ descriptor: PumpManagerDescriptor) {
        self.init(id: descriptor.identifier, title: descriptor.localizedTitle, group: descriptor.manufacturer, image: descriptor.image)
    }

    init(_ descriptor: CGMManagerDescriptor) {
        self.init(id: descriptor.identifier, title: descriptor.localizedTitle, group: descriptor.manufacturer, image: descriptor.image)
    }

    init(_ descriptor: ServiceDescriptor) {
        self.init(id: descriptor.identifier, title: descriptor.localizedTitle, group: descriptor.category, image: descriptor.image)
    }
}
