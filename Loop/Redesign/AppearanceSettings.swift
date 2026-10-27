//
//  AppearanceSettings.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

/// Light, dark or the system's choice, applied to Loop's whole window.
enum LoopAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    private static let key = "com.loopkit.Loop.redesign.appearance"

    static let didChange = Notification.Name("LoopAppearancePreferenceDidChange")

    static var current: LoopAppearancePreference {
        get { UserDefaults.standard.string(forKey: key).flatMap(LoopAppearancePreference.init(rawValue:)) ?? .system }
        set {
            guard newValue != current else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return NSLocalizedString("System", comment: "Appearance option that follows the iPhone's light or dark setting")
        case .light: return NSLocalizedString("Day", comment: "Appearance option that always uses light mode")
        case .dark: return NSLocalizedString("Night", comment: "Appearance option that always uses dark mode")
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The home screen icons Loop ships. Classic is the primary icon; the others are alternate icon sets in DerivedAssetsBase.
enum LoopAppIcon: String, CaseIterable, Identifiable {
    case classic
    case dayAndNight
    case day
    case night

    var id: String { rawValue }

    /// The asset catalog name passed to `setAlternateIconName`; nil is the primary icon.
    var alternateIconName: String? {
        switch self {
        case .classic: return nil
        case .dayAndNight: return "AppIconDayNight"
        case .day: return "AppIconDay"
        case .night: return "AppIconNight"
        }
    }

    var title: String {
        switch self {
        case .classic: return NSLocalizedString("Classic", comment: "Name of Loop's original app icon")
        case .dayAndNight: return NSLocalizedString("Day and Night", comment: "Name of the app icon that follows the home screen's light or dark appearance")
        case .day: return NSLocalizedString("Day", comment: "Name of the light app icon")
        case .night: return NSLocalizedString("Night", comment: "Name of the dark app icon")
        }
    }

    var detail: String? {
        switch self {
        case .dayAndNight: return NSLocalizedString("Changes with the home screen's light or dark appearance", comment: "Description of the app icon that follows the home screen appearance")
        default: return nil
        }
    }

    static var current: LoopAppIcon {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.alternateIconName == name } ?? .classic
    }

    /// The preview shown in Settings. iOS doesn't expose alternate icons as images, so they have their own
    /// preview image sets; Classic is read from the primary icon files, which a workspace may override.
    var preview: UIImage? {
        switch self {
        case .classic: break
        case .dayAndNight: return UIImage(named: "AppIconPreviewDayNight")
        case .day: return UIImage(named: "AppIconPreviewDay")
        case .night: return UIImage(named: "AppIconPreviewNight")
        }
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let entry = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        if let files = entry?["CFBundleIconFiles"] as? [String] {
            for file in files.reversed() {
                if let image = UIImage(named: file) { return image }
            }
        }
        return (entry?["CFBundleIconName"] as? String).flatMap { UIImage(named: $0) }
    }
}

/// Settings → Appearance: day or night for the app, and which icon the home screen shows.
struct AppearanceSettingsView: View {
    @State private var appearance = LoopAppearancePreference.current
    @State private var icon = LoopAppIcon.current
    @State private var iconError: String?

    var body: some View {
        List {
            Section(footer: Text(NSLocalizedString("System follows your iPhone's light or dark setting.", comment: "Footer for the appearance choice"))) {
                Picker(NSLocalizedString("Appearance", comment: "Title of the light or dark appearance choice"), selection: $appearance) {
                    ForEach(LoopAppearancePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { LoopAppearancePreference.current = $0 }
            }

            Section(header: Text(NSLocalizedString("App Icon", comment: "Header for the app icon choice")), footer: iconFooter) {
                ForEach(LoopAppIcon.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        AppIconRow(icon: option, isSelected: option == icon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Appearance", comment: "Title of the appearance settings screen"))
    }

    @ViewBuilder
    private var iconFooter: some View {
        if let iconError {
            Text(iconError).foregroundStyle(LoopDesign.Palette.criticalInk)
        }
    }

    private func choose(_ option: LoopAppIcon) {
        guard option != icon, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            DispatchQueue.main.async {
                // iOS can report an error from the "icon changed" alert even though the icon did change,
                // so the icon iOS now reports decides.
                if let error, UIApplication.shared.alternateIconName != option.alternateIconName {
                    iconError = String(format: NSLocalizedString("The icon couldn't be changed: %@", comment: "Error shown when iOS refuses an app icon change"), error.localizedDescription)
                } else {
                    iconError = nil
                    icon = option
                }
            }
        }
    }
}

private struct AppIconRow: View {
    let icon: LoopAppIcon
    let isSelected: Bool

    var body: some View {
        HStack(spacing: LoopDesign.Space.s3) {
            Group {
                if let image = icon.preview {
                    Image(uiImage: image).resizable()
                } else {
                    LoopDesign.Palette.surfaceSunken
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LoopDesign.Palette.separator, lineWidth: 0.5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(icon.title)
                    .foregroundStyle(LoopDesign.Palette.ink)
                if let detail = icon.detail {
                    Text(detail)
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(LoopDesign.Palette.inkMuted)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoopDesign.Palette.accent)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
