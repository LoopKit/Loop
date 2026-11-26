import ActivityKit
import LoopCore
import LoopKit
import UIKit

@available(iOS 16.2, *)
@MainActor
protocol LiveActivityClient {
    var activitiesEnabled: Bool { get }
    var canCreateActivity: Bool { get }
    func needsRecreation(settings: LiveActivitySettings) -> Bool
    func endActivities() async
    func publish(_ state: GlucoseActivityAttributes.ContentState, settings: LiveActivitySettings) async throws
}

/// Owns ActivityKit operations. The manager serializes calls to this client.
@available(iOS 16.2, *)
@MainActor
final class ActivityKitLiveActivityClient: LiveActivityClient {
    private var activity: Activity<GlucoseActivityAttributes>?
    private var activitySettings: LiveActivitySettings?
    private var startDate = Date.now

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var canCreateActivity: Bool { UIApplication.shared.applicationState == .active }

    func needsRecreation(settings: LiveActivitySettings) -> Bool {
        guard let activity else { return false }
        if activitySettings != settings { return true }
        switch activity.activityState {
        case .active:
            return Date.now.timeIntervalSince(startDate) > .hours(1)
        default:
            return true
        }
    }

    func endActivities() async {
        for activity in Activity<GlucoseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        activitySettings = nil
    }

    func publish(_ state: GlucoseActivityAttributes.ContentState, settings: LiveActivitySettings) async throws {
        let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(.hours(1)))
        if let activity {
            await activity.update(content)
        } else if canCreateActivity {
            activity = try Activity.request(
                attributes: GlucoseActivityAttributes(
                    mode: settings.mode,
                    addPredictiveLine: settings.addPredictiveLine,
                    useLimits: settings.useLimits,
                    upperLimitChartMmol: settings.upperLimitChartMmol,
                    lowerLimitChartMmol: settings.lowerLimitChartMmol,
                    upperLimitChartMg: settings.upperLimitChartMg,
                    lowerLimitChartMg: settings.lowerLimitChartMg
                ),
                content: content,
                pushType: .token
            )
            activitySettings = settings
            startDate = .now
        }
    }
}
