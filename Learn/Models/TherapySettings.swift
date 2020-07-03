//
//  TherapySettings.swift
//  Learn
//
//  Created by Pete Schwamb on 5/10/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore

protocol TherapySettings {
    var momentumDataInterval: TimeInterval { get }
    var insulinModel: InsulinModelSettings { get }
    var basalSchedule: BasalRateSchedule { get }
    var sensitivity: InsulinSensitivitySchedule { get }
    var carbRatios: CarbRatioSchedule { get }
    var absorptionTimeOverrun: Double { get }
    var defaultAbsorptionTime: TimeInterval { get }
    var carbAbsortionModel: CarbAbsorptionModel { get }
    var carbEffectDelay: TimeInterval { get }
    var retrospectiveCorrectionGroupingInterval: TimeInterval { get }
    var retrospectiveCorrection: RetrospectiveCorrection { get }
    var delta: TimeInterval { get }
    var inputDataRecencyInterval: TimeInterval { get }
}

extension TherapySettings {
    var carbModelSettings: CarbModelSettings {
        return carbAbsortionModel.settings(with: absorptionTimeOverrun)
    }
}

