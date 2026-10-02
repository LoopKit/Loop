//
//  ExtensionDelegate+PodLoan.swift
//  WatchApp Extension
//
//  Sport Mode on the watch app's delegate: shared-instance registration, the loan stack, and
//  the WatchConnectivity callbacks loan traffic arrives on.
//

import Foundation
import LoopCore
import LoopKit
import G7SensorKit
import UserNotifications
import WatchConnectivity
import WatchKit

extension ExtensionDelegate {

    // MARK: The delegate instance

    /// Registered by the delegate itself: under the SwiftUI lifecycle
    /// `WKApplication.shared().delegate` is always nil.
    private static var installed: ExtensionDelegate?

    /// nil before the delegate exists; `shared()` would trap.
    static func sharedIfAvailable() -> ExtensionDelegate? {
        return installed
    }

    /// Called as the first statement of `init()`.
    func podLoanRegisterSharedInstance() {
        // First, before SwiftUI can construct a view that asks for the delegate.
        Self.installed = self
    }

    // MARK: The Sport Mode stack

    /// Built at launch (opening the stores is async); a message landing before it is ready is logged.
    private func startStockLoopSession() {
        guard FeatureFlags.sportModeEnabled, stockLoopSession == nil, !stockLoopSessionStarting else { return }
        stockLoopSessionStarting = true
        // Off the main actor: opening stores and a BLE central is not main-thread work.
        Task.detached(priority: .userInitiated) {
            let session = await StockLoopSession()
            await MainActor.run {
                self.stockLoopSession = session
                self.stockLoopSessionStarting = false
                if session == nil {
                    // Sport Mode is unavailable; the rest of the watch app is not affected.
                    SportLog.event("session", "SPORT MODE UNAVAILABLE — stack did not assemble")
                } else {
                    session?.sessionDidActivate()
                }
            }
        }
    }

    // MARK: App lifecycle

    /// Called from `applicationDidFinishLaunching()`. With the flag off, nothing of Sport Mode starts.
    func podLoanDidFinishLaunching() {
        guard FeatureFlags.sportModeEnabled else { return }
        NotificationCenter.default.addObserver(forName: G7CGMManager.statusDidChange, object: nil, queue: .main) { note in
            guard let manager = note.object as? G7CGMManager else { return }
            if !manager.isSearchingForSensor {
                SensorSearchAlert.disarm()
            } else if WKApplication.shared().applicationState != .active {
                SensorSearchAlert.arm()
            }
        }
        WatchAlertPresenter.registerCategory()
        // At launch, so the first loan message has somewhere to go; failure only disables Sport Mode.
        SportLog.event("session", "launch: starting Sport Mode stack")
        startStockLoopSession()
    }

    /// A wrist alert's response stays on the wrist; acknowledging the loaned pump's reaches the pump.
    func podLoanHandleAlertResponse(_ response: UNNotificationResponse) async -> Bool {
        let request = response.notification.request
        guard FeatureFlags.sportModeEnabled, WatchAlertPresenter.isWristAlert(request.identifier) else { return false }
        guard WatchAlertPresenter.acknowledges(response.actionIdentifier),
              let identifier = WatchAlertPresenter.alertIdentifier(in: request.content.userInfo) else { return true }
        stockLoopSession?.stack.loopManager.recordAlertAcknowledgement(identifier)
        guard let responder = await stockLoopSession?.loanController.pumpAlertResponder(for: identifier.managerIdentifier) else {
            SportLog.event("alert", "ACKNOWLEDGED \(identifier.value) on the wrist — not the loaned pump's, nothing to pass on")
            return true
        }
        await WatchAlertPresenter.acknowledge(identifier, with: responder, content: request.content)
        return true
    }

    /// Called from `applicationDidBecomeActive()`.
    func podLoanDidBecomeActive() {
        guard FeatureFlags.sportModeEnabled else { return }
        // Foreground: re-assert the workout session if anything holds it.
        startStockLoopSession()
        stockLoopSession?.ensureKeepalive()
        SportLog.event("lifecycle", "didBecomeActive [lifecycle-crumb]")
        NotificationCenter.default.post(name: Self.didBecomeActiveNotification, object: self)
        SensorSearchAlert.disarm()
    }

    /// Called from `applicationWillResignActive()`.
    func podLoanWillResignActive() {
        guard FeatureFlags.sportModeEnabled else { return }
        // Lifecycle breadcrumb.
        SportLog.event("lifecycle", "willResignActive [lifecycle-crumb]")
        NotificationCenter.default.post(name: Self.willResignActiveNotification, object: self)
        if (stockLoopSession?.stack.loopManager.cgmManager as? G7CGMManager)?.isSearchingForSensor == true {
            SensorSearchAlert.arm()
        }
    }

    /// Foreground transitions for SwiftUI pages.
    static let didBecomeActiveNotification = Notification.Name("com.loopkit.Loop.LoopWatch.didBecomeActive")
    static let willResignActiveNotification = Notification.Name("com.loopkit.Loop.LoopWatch.willResignActive")

    // MARK: WatchConnectivity

    /// Called from `session(_:activationDidCompleteWith:error:)`.
    func podLoanSessionDidActivate() {
        stockLoopSession?.sessionDidActivate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard FeatureFlags.sportModeEnabled else { return }
        SportLog.event("wc", "REACHABILITY CHANGED — reachable=\(session.isReachable) "
                           + "activation=\(session.activationState.rawValue)")
        // A seized loan prompts when the phone genuinely returns.
        stockLoopSession?.loanController.noteReachabilityChanged(session.isReachable)
    }

    /// The immediate channel, which the grant arrives on. Without this method WatchConnectivity drops
    /// `sendMessage(_:replyHandler: nil)` silently. Mirrors the phone-side method in WatchDataManager.
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let stockLoopSession {
            if stockLoopSession.handleIncomingIfLoanMessage(message, channel: .urgent) { return }
        } else if FeatureFlags.sportModeEnabled, message[LoanProtocol.userInfoKey] != nil {
            // Logged and the stack started, not discarded.
            log.error("Loan payload arrived on the urgent channel before the Sport Mode stack finished starting")
            startStockLoopSession()
            return
        }
        log.default("Ignoring unexpected sendMessage: %{public}@", String(describing: Array(message.keys)))
    }

    /// The queued channel's half of the same recovery, called from `didReceiveUserInfo`.
    func podLoanNoteEarlyPayload() {
        guard FeatureFlags.sportModeEnabled else {
            log.default("Ignoring a loan payload: Sport Mode is off in this build")
            return
        }
        log.error("Loan payload arrived before the Sport Mode stack finished starting")
        startStockLoopSession()
    }
}
