//
//  VersionUpdateViewModel.swift
//  Loop
//
//  Created by Rick Pasetto on 10/4/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Combine
import Foundation
import LoopKit
import SwiftUI
import LoopKitUI

public class VersionUpdateViewModel: ObservableObject {
    
    @Published var versionUpdate: VersionUpdate?

    var softwareUpdateAvailable: Bool {
        return versionUpdate?.softwareUpdateAvailable ?? false
    }
    
    @ViewBuilder
    var icon: some View {
        switch versionUpdate {
        case .required, .recommended:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(warningColor)
        default:
            EmptyView()
        }
    }
    
    func footer(appName: String) -> String {
        switch versionUpdate {
        case .required, .recommended:
            return String(format: NSLocalizedString("A new version of %@ is available and is recommended to continue using the app.", comment: "Software update available section footer (1: app name)"), appName)
        case .available:
            return String(format: NSLocalizedString("A new version of %@ is available.", comment: "Required software update section footer (1: app name)"), appName)
        default:
            return ""
        }
    }
    
    @ViewBuilder
    var softwareUpdateView: some View {
        supportManager?.softwareUpdateView(guidanceColors: guidanceColors)
    }
    
    var warningColor: Color {
        switch versionUpdate {
        case .required: return guidanceColors.critical
        case .recommended: return guidanceColors.warning
        default: return .primary
        }
    }
    
    private weak var supportManager: SupportManager?
    private let guidanceColors: GuidanceColors

    lazy private var cancellables = Set<AnyCancellable>()

    init(supportManager: SupportManager? = nil, guidanceColors: GuidanceColors) {
        self.supportManager = supportManager
        self.guidanceColors = guidanceColors
        
        NotificationCenter.default.publisher(for: .SoftwareUpdateAvailable)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)
        
        update()
    }
    
    public func update() {
        Task { @MainActor in
            versionUpdate = await supportManager?.checkVersion()
        }
    }
}
