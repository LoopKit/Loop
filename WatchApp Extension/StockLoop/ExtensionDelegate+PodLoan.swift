//
//  ExtensionDelegate+PodLoan.swift
//  WatchApp Extension
//
//  Everything Sport Mode adds to the watch app's delegate: the shared-instance registration,
//  starting and holding the loan stack, the foreground breadcrumbs, and the WatchConnectivity
//  callbacks the loan traffic arrives on.
//
//  The stock delegate keeps only its stored properties and one-line `podLoan…` hooks.
//

import Foundation
import LoopCore
import WatchConnectivity
import WatchKit

extension ExtensionDelegate {

    // MARK: The delegate instance

    /// The live delegate, registered by the delegate itself.
    ///
    /// Deliberately NOT `WKApplication.shared().delegate`. Under the SwiftUI application
    /// lifecycle the delegate is created and owned by `@WKApplicationDelegateAdaptor`, and that
    /// property is never populated — it reads nil for the whole life of the app even while THIS
    /// object is receiving every lifecycle callback. The old WatchKit extension installed its
    /// delegate from Info.plist, which is the only reason the same lookup worked there.
    ///
    /// The failure mode is worth remembering because it is silent: every view asking for the
    /// delegate got nil, so `stockLoopSession` read nil, so the Start button and the diagnostics
    /// controls did nothing whatsoever — no error, no log line, a UI that renders correctly and is
    /// completely inert. The launch crash that preceded it was the same nil arriving through
    /// `shared()`, which is implicitly unwrapped and therefore trapped instead of returning.
    private static var installed: ExtensionDelegate?

    /// The delegate, or nil if it does not exist yet.
    ///
    /// Anything reachable from view construction must ask this way: `shared()` traps on nil, and
    /// SwiftUI can evaluate a `@StateObject` initializer before the delegate is constructed.
    static func sharedIfAvailable() -> ExtensionDelegate? {
        return installed
    }

    /// Called as the first statement of `init()`.
    func podLoanRegisterSharedInstance() {
        // Register FIRST, before any other setup: SwiftUI can construct a view — and a
        // @StateObject initializer that reaches for the delegate — as soon as this object exists
        // and before applicationDidFinishLaunching runs. That window is where the launch crash
        // happened, and registering late would leave it open.
        Self.installed = self
    }

    // MARK: The Sport Mode stack

    /// The Sport Mode stack: the watch's own loop, the loan controller, the CGM transport and
    /// the workout keepalive that holds the app awake between doses.
    ///
    /// Optional rather than `lazy` because building it opens the dose store, which is async now.
    /// It is started at launch — before any loan message can arrive — and a message that lands
    /// in the gap is logged rather than dropped silently.
    private func startStockLoopSession() {
        guard stockLoopSession == nil, !stockLoopSessionStarting else { return }
        stockLoopSessionStarting = true
        // Built OFF the main actor and hopped back only to publish the result. Opening three
        // Core Data stores and a BLE central is not main-thread work, and on a watch the launch
        // window is short enough that doing it there risks the app being killed for being
        // unresponsive before it has drawn anything.
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

    /// Called from `applicationDidFinishLaunching()`.
    func podLoanDidFinishLaunching() {
        // Start the loan stack HERE, not on first use: the loan's transport callbacks land on
        // this delegate, and a stack that only builds when something arrives would miss the
        // message that was meant to build it. It is built off-main and cannot fail the launch:
        // if it does not assemble, Sport Mode is simply unavailable.
        SportLog.event("session", "launch: starting Sport Mode stack")
        startStockLoopSession()
    }

    /// Called from `applicationDidBecomeActive()`.
    func podLoanDidBecomeActive() {
        // Re-assert the workout session if anything still holds it. This is the one moment we
        // KNOW we are executing — the only other re-assert path is a timer, which cannot fire
        // while suspended. No-op when nothing holds it.
        startStockLoopSession()
        stockLoopSession?.ensureKeepalive()
        SportLog.event("lifecycle", "didBecomeActive [lifecycle-crumb]")
        NotificationCenter.default.post(name: Self.didBecomeActiveNotification, object: self)
    }

    /// Called from `applicationWillResignActive()`.
    func podLoanWillResignActive() {
        // Breadcrumb for the silent-death investigation: the deaths cluster in the
        // radio-quiet window, and the app's exact lifecycle state at last breath is the
        // discriminator between watchdog-on-transition and background-kill theories.
        SportLog.event("lifecycle", "willResignActive [lifecycle-crumb]")
        NotificationCenter.default.post(name: Self.willResignActiveNotification, object: self)
    }

    /// Foreground transitions, as notifications. A SwiftUI page that only wants to work while
    /// it is actually being looked at keys its refresh off these.
    static let didBecomeActiveNotification = Notification.Name("com.loopkit.Loop.LoopWatch.didBecomeActive")
    static let willResignActiveNotification = Notification.Name("com.loopkit.Loop.LoopWatch.willResignActive")

    // MARK: WatchConnectivity

    /// Called from `session(_:activationDidCompleteWith:error:)`.
    func podLoanSessionDidActivate() {
        stockLoopSession?.sessionDidActivate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        SportLog.event("wc", "REACHABILITY CHANGED — reachable=\(session.isReachable) "
                           + "activation=\(session.activationState.rawValue)")
        // R40 reunion: a seized loan PROMPTS (debounced, R40(f)) when the phone genuinely
        // returns — the controller ignores everything but that case.
        stockLoopSession?.loanController.noteReachabilityChanged(session.isReachable)
    }

    /// The IMMEDIATE channel — and the one the phone's GRANT arrives on.
    ///
    /// `sendMessage(_:replyHandler:nil)` is delivered here, NOT to `didReceiveUserInfo`. Without
    /// this method the interactive half of the loan handshake is dropped by WatchConnectivity with
    /// no error on either side: the phone logs a grant sent and then reclaims the pod 20s later
    /// having never been acked, and the wrist sits on "awaiting grant" until its own timeout and
    /// reports the hand-over never arrived. Both devices behave correctly and the loan still
    /// cannot start.
    ///
    /// Its fingerprint in the watch log is that EVERY inbound line reads `ch=queued` while the
    /// watch's own sends read `path urgent` — i.e. the fast channel works outbound and silently
    /// does not exist inbound.
    ///
    /// This is the exact mirror of the phone-side gap in WatchDataManager; both halves of the
    /// urgent channel were lost in the port, and each one hides the other: fixing only the phone
    /// moves the failure from "no response" to "hand-over never reached the watch".
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let stockLoopSession {
            if stockLoopSession.handleIncomingIfLoanMessage(message, channel: .urgent) { return }
        } else if message[LoanProtocol.userInfoKey] != nil {
            // Same recovery as the queued path: a grant that arrives before the stack is up is
            // logged and the stack started, rather than silently discarded.
            log.error("Loan payload arrived on the urgent channel before the Sport Mode stack finished starting")
            startStockLoopSession()
            return
        }
        log.default("Ignoring unexpected sendMessage: %{public}@", String(describing: Array(message.keys)))
    }

    /// The queued channel's half of the same recovery, called from `didReceiveUserInfo`.
    func podLoanNoteEarlyPayload() {
        log.error("Loan payload arrived before the Sport Mode stack finished starting")
        startStockLoopSession()
    }
}
