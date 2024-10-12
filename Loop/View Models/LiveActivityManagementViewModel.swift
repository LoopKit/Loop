//
//  LiveActivityManagementViewModel.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 12/09/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore

class LiveActivityManagementViewModel : ObservableObject {
    @Published var enabled: Bool
    @Published var mode: LiveActivityMode
    @Published var isEditingMode: Bool = false
    @Published var alwaysEnabled: Bool = true
    @Published var showWhenLowIsPredicted = true
    @Published var showWhenHighIsPredicted = true
    @Published var addPredictiveLine: Bool
    @Published var useLimits: Bool
    @Published var upperLimitChartMmol: Double
    @Published var lowerLimitChartMmol: Double
    @Published var upperLimitChartMg: Double
    @Published var lowerLimitChartMg: Double
    
    init() {
        let liveActivitySettings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
        
        self.enabled = liveActivitySettings.enabled
        self.mode = liveActivitySettings.mode
        self.addPredictiveLine = liveActivitySettings.addPredictiveLine
        self.useLimits = liveActivitySettings.useLimits
        self.alwaysEnabled = liveActivitySettings.alwaysEnabled
        self.showWhenLowIsPredicted = liveActivitySettings.showWhenLowIsPredicted
        self.showWhenHighIsPredicted = liveActivitySettings.showWhenHighIsPredicted
        self.upperLimitChartMmol = liveActivitySettings.upperLimitChartMmol
        self.lowerLimitChartMmol = liveActivitySettings.lowerLimitChartMmol
        self.upperLimitChartMg = liveActivitySettings.upperLimitChartMg
        self.lowerLimitChartMg = liveActivitySettings.lowerLimitChartMg
    }
}
