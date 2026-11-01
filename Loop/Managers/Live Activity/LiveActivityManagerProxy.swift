//
//  LiveActivityManagerProxy.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 01/11/2025.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol LiveActivityManagerProxy {
    /// Update the live activity with current override and glucose target information.
    /// Call this whenever overrides or glucose targets change, or after every loop cycle.
    func update(
        scheduleOverride: TemporaryScheduleOverride?,
        preMealOverride: TemporaryScheduleOverride?,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule?,
        activeInsulin: InsulinValue?
    )
}
