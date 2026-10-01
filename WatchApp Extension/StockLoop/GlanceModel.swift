//
//  GlanceModel.swift
//  WatchApp Extension
//
//  What the glance draws and the rules that derive it; GlanceView decides nothing. Reads only
//  mirrors, never the loop or loan queue.
//

import Foundation
import SwiftUI
import Combine
import WatchKit
import HealthKit
import LoopKit
import LoopCore
import G7SensorKit

/// One frame of the glance. Every field is already decided — the view formats and lays out, and
/// asks no questions of the app.
struct GlanceUIState {
    /// Chooses the layout. A hand-back still dosing stays `.active` with `handbackPending`.
    enum Phase { case idle, starting, active, handingBack, draining }

    /// `.dim` is not a range. It is the colour of a number this page is not vouching for — a
    /// stale reading, or the phone's relay while the loop is not ours — whatever its value.
    enum BGColor { case inRange, high, low, dim }

    /// `.unknown` means NO cycle has ever completed, not "an old one did". The ring greys for it
    /// rather than showing red, because red is a failure of a loop that was working.
    enum LoopFreshness { case fresh, aging, stale, unknown }

    var phase: Phase = .idle
    var bgText: String = "—"
    var trendSymbol: String? = nil
    var bgColor: BGColor = .dim

    /// Set only when the glucose is stale, and then it says how old in words. A stale reading is
    /// dimmed and EXPLAINED, never blanked.
    var staleAgeText: String? = nil
    var eventualText: String? = nil
    var iobText: String = "—"
    var cobText: String = "—"
    var tempText: String = "—"
    var loopStatusText: String = ""
    var loopFreshness: LoopFreshness = .unknown

    /// The eventual is from a stale cycle: marked, not hidden.
    var predictionStale: Bool = false

    /// Shown in the phoneless-start confirmation, never enforced.
    var seizeOfferAgeText: String? = nil

    var reunionPrompt: Bool = false
    var viaPhone: Bool = false

    /// Which device the glucose on screen came from. It is stamped on arrival rather than read
    /// back from the store, so it answers "is this watch standing on its own right now?".
    enum BGSource { case directG7, phoneRelay, none }
    var bgSource: BGSource = .none

    /// A short-lived line that displaces the provenance line: a bolus being sent, a hand-back
    /// draining, a failure worth seeing once. Each carries its own expiry — see `refresh`.
    var transientText: String? = nil

    var loopClosed: Bool = false

    /// A sentence under the centre block, shown when something needs saying in words rather than
    /// numbers. Used on the idle page and while a hand-back waits for the phone.
    var idleNote: String? = nil

    var phoneUnreachable: Bool = false

    /// When the pod takeover began. It drives the one determinate progress bar on this page, and
    /// is set for the takeover stage only — never for the open-ended wait on the phone.
    var startedAt: Date? = nil

    var startingStageText: String? = nil

    /// First contact with a new pod needs the screen on: the Start note, then the takeover hint.
    var firstContactNote: String? = nil
    var takeoverHint: String? = nil
    var takeoverHintDone: Bool = false

    /// Provenance, next-reading countdown or wedge hint; the hint wins.
    var g7EtaText: String? = nil

    /// A bolus the pod is delivering, with the pump manager's progress reporter for it.
    var bolusDelivery: (units: Double, reporter: DoseProgressReporter)? = nil

    var overrideLabel: String? = nil

    /// A hand-back is draining while the watch keeps dosing. This is the cancellable window, and
    /// it is why the top-right chip becomes Cancel instead of End.
    var handbackPending: Bool = false

    var handbackStartedAt: Date? = nil
}

/// Repaints come from the 2 s tick, the mirror observer, explicit refreshes and the freshness
/// boundary timer (ageing pushes nothing).
@MainActor
final class GlanceViewModel: ObservableObject {
    @Published var state = GlanceUIState()

    /// Hides the idle frame until the first controller snapshot is read.
    @Published var hasControllerState = false

    /// Read from the controller's NON-BLOCKING mirrors. Both are consulted from main while the
    /// loan queue may be busy with the pod, which is exactly why neither may be a queue read.
    var loanIsLive: Bool {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.isLoanActiveNonBlocking ?? false
    }

    var isResuming: Bool {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.isResumingNonBlocking ?? false
    }

    /// Every phase but idle, so the user lands on a stalled loop.
    var wantsFocus: Bool {
        switch state.phase {
        case .starting, .active, .handingBack, .draining: return true
        case .idle: return false
        }
    }

    /// The on-screen tick. Two seconds is the page's own clock: the elapsed counters, the bolus
    /// bar and the transient notes' expiries all age against it, and none of them are pushed.
    private var timer: Timer?

    /// COB is async; the cached value's time rides the render log.
    private var latestCOB: Double?

    private var lastRenderLogAt: Date?
    private var lastRenderLogKey: String?
    private var latestCOBAt: Date?
    private var appStateObservers: [NSObjectProtocol] = []

    /// Previews drive the real view with hand-written state and reach nothing.
    private let isPreview: Bool

    /// One G7 grid point plus grace. Display only; never licenses a dose.
    private static let displayStaleAge: TimeInterval = 7 * 60

    /// Two digits, matching the pod's 0.05 U pulses.
    static let unitsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    init() {
        isPreview = false

        observeAppState()
    }

    /// From the extension delegate: an undim delivers no `onAppear`.
    private func observeAppState() {
        let center = NotificationCenter.default
        appStateObservers = [
            center.addObserver(forName: ExtensionDelegate.didBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.startRefreshing()
            },
            center.addObserver(forName: ExtensionDelegate.willResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.stopRefreshing()
            },
        ]
    }

    /// Survives `stopRefreshing` on purpose — see there.
    private var mirrorObserver: NSObjectProtocol?

    /// The observer must not kick the mirror: a kick republishes, which re-notifies without bound.
    func startRefreshing() {
        guard !isPreview else { return }
        RuntimeStateLog.mark("glance.startRefreshing")
        SportLog.event("glance", "render loop STARTED [glance-life]")
        if let o = oneShotMirrorObserver { NotificationCenter.default.removeObserver(o); oneShotMirrorObserver = nil }
        if mirrorObserver == nil {
            mirrorObserver = NotificationCenter.default.addObserver(
                forName: WatchLoopManager.glanceMirrorDidUpdate, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh(kickMirror: false) }
        }

        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private var boundaryTimer: Timer?

    /// Repaints at 6 and 16 min past the last cycle (LoopKit's cut-offs); re-armed after each refresh.
    private func armFreshnessBoundaryRepaint() {
        boundaryTimer?.invalidate(); boundaryTimer = nil
        guard state.phase == .active,
              let last = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.loopManager.mirroredGlanceData?.lastLoopCompleted
        else { return }
        let age = Date().timeIntervalSince(last)
        let boundaries: [TimeInterval] = [6 * 60, 16 * 60]
        guard let next = boundaries.first(where: { $0 > age }) else { return }
        let delay: TimeInterval = next - age + 1
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            SportLog.event("glance", "freshness boundary passed — self-repaint [glance-life]")
            self?.refreshNow()
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        boundaryTimer = t
    }

    private var oneShotMirrorObserver: NSObjectProtocol?

    /// For a phase or bolus change; arms a one-shot when no observer is standing.
    func refreshNow() {
        guard !isPreview else { return }
        RuntimeStateLog.mark("glance.refreshNow")
        if mirrorObserver == nil, oneShotMirrorObserver == nil {
            oneShotMirrorObserver = NotificationCenter.default.addObserver(
                forName: WatchLoopManager.glanceMirrorDidUpdate, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                if let o = self.oneShotMirrorObserver {
                    NotificationCenter.default.removeObserver(o)
                    self.oneShotMirrorObserver = nil
                }
                self.refresh(kickMirror: false)
            }
        }
        refresh()
    }

    /// Stops the tick only; the observer stays to repaint a face-up watch.
    func stopRefreshing() {
        RuntimeStateLog.mark("glance.stopRefreshing")
        SportLog.event("glance", "render loop STOPPED [glance-life]")

        timer?.invalidate()
        timer = nil
    }

    init(preview: GlanceUIState) {
        isPreview = true
        state = preview
    }

    deinit {
        if let o = mirrorObserver { NotificationCenter.default.removeObserver(o) }
        if let o = oneShotMirrorObserver { NotificationCenter.default.removeObserver(o) }
        timer?.invalidate()
        appStateObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // Actions flip the field locally, hand off, and refresh shortly after the controller republishes.

    func cancelHandback() {
        guard !isPreview else { return }

        WKInterfaceDevice.current().play(.click)
        state.handbackPending = false

        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.cancelHandback()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func confirmSeize() {
        guard !isPreview else { return }
        RuntimeStateLog.mark("glance.confirmSeize")
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.confirmSeize()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func dismissSeize() {
        guard !isPreview else { return }
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.dismissSeize()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func startSportMode() {
        RuntimeStateLog.mark("glance.startSportMode")
        guard !isPreview else { return }

        let build = BuildDetails.default.codeIdentity

        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession else {
            let why = ExtensionDelegate.sharedIfAvailable() == nil ? "no app delegate" : "no session"
            SportLog.event("session", "START TAPPED but Sport Mode is unavailable (\(why)) — the stack never assembled · build \(build)")
            return
        }

        session.loanController.requestLoan(watchBuild: build)

        // Snapshots at the tap and after, since a dark watch cannot send one later.
        session.sendLogSnapshot("sport start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) {
            session.sendLogSnapshot("start +35s")
        }
        refresh()
    }

    /// The watch keeps dosing and stays cancellable until the phone acks the records.
    func endSportMode() {
        RuntimeStateLog.mark("glance.endSportMode")
        guard !isPreview else { state.handbackPending = true; return }

        WKInterfaceDevice.current().play(.click)
        state.handbackPending = true

        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.beginHandback()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    /// The watch's own loop mode; never combined with the phone's.
    func setLoopClosed(_ closed: Bool) {
        guard !isPreview else {
            state.loopClosed = closed
            state.loopStatusText = closed ? "CLOSED · 0m" : "OPEN"
            return
        }
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.loopManager.setClosedLoopEnabled(closed)
        refresh()
    }

    /// The controller's phase picks the page; the loop mirror fills the numbers. Breadcrumbs
    /// name the step if main wedges here.
    private func refresh(kickMirror: Bool = true) {
        guard !isPreview else { return }
        RuntimeStateLog.mark("glance.refresh(kick:\(kickMirror))")
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession else { return }

        RuntimeStateLog.mark("glance.refresh.debugSnap")
        session.loanController.refreshDebugSnapshot()
        RuntimeStateLog.mark("glance.refresh.mirrorRead")
        // Nothing is drawn from a missing snapshot — the page keeps its previous frame rather
        // than falling back to the default `.idle` state, which would advertise Start mid-loan.
        guard let snap = session.loanController.mirroredDebugSnapshot else { return }
        if !hasControllerState { hasControllerState = true }
        RuntimeStateLog.mark("glance.refresh.phase(\(snap.phase.rawValue))")
        // Deferred so EVERY path re-arms the boundary, including the arms below that return
        // early. A refresh that skipped it would leave the page with no way to notice ageing.
        defer { armFreshnessBoundaryRepaint() }

        let cgm = session.stack.loopManager.cgmManager as? G7CGMManager
        let sensorNote = G7WatchDirectRead.needsCodeNote(for: cgm?.watchNeedsCodeFor) ?? G7WatchDirectRead.searchingNote(cgm?.watchIsSearching ?? false)

        switch snap.phase {
        case .idle:

            // The note slot has one occupant. The controller's own note wins over the sensor-code
            // prompt: whatever just happened to a session matters more than a standing setup task.
            var idle = Self.idleState(context: ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext,
                                      note: snap.lastIdleNote ?? sensorNote)

            if let issued = snap.seizeOfferIssuedAt {
                let f = DateComponentsFormatter()
                f.maximumUnitCount = 1
                f.allowedUnits = [.day, .hour, .minute]
                f.unitsStyle = .abbreviated
                idle.seizeOfferAgeText = f.string(from: Date().timeIntervalSince(issued)) ?? "?"
            }
            if snap.pumpFirstContactExpected { idle.firstContactNote = PodLoanWatchController.firstContactStartNote }
            state = idle
        // One UI phase for both, so a slow takeover does not look like a failure.
        case .requested, .takingOver:
            var starting = Self.startingState(context: ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext,
                                              takingOver: snap.phase == .takingOver,
                                              startedAt: snap.startedAt,
                                              now: Date())
            starting.takeoverHint = snap.takeoverHint
            starting.takeoverHintDone = snap.takeoverPodReached
            state = starting
        // The pod stays here until the phone acks the records; the notes say so.
        case .handingBack:
            var s = GlanceUIState(); s.phase = .handingBack

            s.handbackStartedAt = snap.handbackStartedAt

            s.loopStatusText = NSLocalizedString("ending…", comment: "Glance status during hand-back")

            s.phoneUnreachable = !snap.phoneReachable
            s.idleNote = snap.phoneReachable
                ? NSLocalizedString("Waiting for iPhone — pod still on watch. Bolus unavailable until it connects.", comment: "Glance note while a hand-back waits for the phone")
                : NSLocalizedString("Can't reach iPhone — pod still on watch. Move it closer or check its Bluetooth.", comment: "Glance note while a hand-back waits for an UNREACHABLE phone")
            state = s
        // A parked drain is startable: the idle page plus a note.
        case .recoveredDrain:

            var restIdle = Self.idleState(context: ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext,
                                          note: snap.lastIdleNote
                                            ?? sensorNote
                                            ?? NSLocalizedString("Records from the last session are waiting for your iPhone. You can still start.",
                                                                 comment: "Glance note while resting on a parked drain"))
            if let issued = snap.seizeOfferIssuedAt {
                let f = DateComponentsFormatter()
                f.maximumUnitCount = 1
                f.allowedUnits = [.day, .hour, .minute]
                f.unitsStyle = .abbreviated
                restIdle.seizeOfferAgeText = f.string(from: Date().timeIntervalSince(issued)) ?? "?"
            }
            if snap.pumpFirstContactExpected { restIdle.firstContactNote = PodLoanWatchController.firstContactStartNote }
            state = restIdle
        // The phone took the pod back. Nothing is left to offer the user and nothing is
        // cancellable — only the records are still owed — so the page says exactly that.
        case .revoked:
            var s = GlanceUIState(); s.phase = .draining
            s.handbackStartedAt = snap.handbackStartedAt

            s.loopStatusText = NSLocalizedString("returning records…", comment: "Glance status while draining records")
            state = s
        case .active:

            RuntimeStateLog.mark("glance.refresh.kickGlance")
            if kickMirror { session.stack.loopManager.refreshGlanceData() }
            guard let data = session.stack.loopManager.mirroredGlanceData else { return }
            RuntimeStateLog.mark("glance.refresh.activeStateBuild")
            var s = Self.activeState(data: data, cob: latestCOB, now: Date(),
                                     phoneGlucoseDate: ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext?.glucoseDate)
            // One transient slot: hand-back in progress, then recent failure, then start note.
            if snap.handbackPending {
                s.handbackPending = true
                s.handbackStartedAt = snap.handbackStartedAt
                s.loopStatusText = NSLocalizedString("ending…", comment: "Glance status while a hand-back drains in the background")

                s.transientText = s.loopStatusText

                // Still looping, and saying so: the pod has not moved, and the copy names the
                // WATCH-to-phone link rather than implying that dosing has stopped.
                s.phoneUnreachable = !snap.phoneReachable
                if !snap.phoneReachable {
                    s.idleNote = NSLocalizedString("Can't reach iPhone — still looping. Move it closer or check its Bluetooth.", comment: "Glance note when an interim hand-back is blocked by an unreachable phone")
                }
            } else if let at = snap.handbackFailedAt, let text = snap.handbackFailureText,
                      Date().timeIntervalSince(at) < 20 {
                s.transientText = text
            } else if let at = snap.startNoteAt, let text = snap.startNoteText,
                      Date().timeIntervalSince(at) < 90 {
                s.transientText = text
            }
            s.reunionPrompt = snap.reunionPromptVisible

            // Narrate the wait for a manual bolus after a short delay, so the user does not End mid-dose.
            if let startedAt = session.stack.loopManager.manualBolusStartedAt {
                let pending = session.stack.loopManager.manualBolusPendingUnits
                let amount = pending.map { Self.unitsFormatter.string(from: NSNumber(value: $0)) ?? String($0) }

                let elapsed = Date().timeIntervalSince(startedAt)
                s.transientText = elapsed < 0.4 ? nil
                    : elapsed < 20
                    ? (amount.map { String(format: NSLocalizedString("starting %@ U…", comment: "Glance status while a manual bolus is being sent to the pod (1: units)"), $0) }
                        ?? NSLocalizedString("starting bolus…", comment: "Glance status while a manual bolus is being sent, amount unknown"))

                    : (amount.map { String(format: NSLocalizedString("taking longer than usual — %@ U will deliver", comment: "Glance status when a manual bolus is slow to reach the pod (1: units)"), $0) }
                        ?? NSLocalizedString("taking longer than usual — the bolus will deliver", comment: "Glance status when a slow manual bolus has no known amount"))
            }

            // Once the pod has accepted, the delivery bar replaces the narration — the two
            // describe the same dose and must never be on screen together.
            if let delivery = session.stack.loopManager.manualBolusDelivery {
                s.bolusDelivery = delivery
                s.transientText = nil
            }
            RuntimeStateLog.mark("glance.refresh.statePublish")
            state = s
            RuntimeStateLog.mark("glance.refresh.logRender")
            logRender(iob: data.iob, cob: latestCOB, glucoseDate: data.glucoseDate, now: Date())
            RuntimeStateLog.mark("glance.refresh.carbFetchDispatch")
            // COB arrives asynchronously, so this frame drew the previous value and only a CHANGE
            // earns a second pass. Unconditional re-entry here would turn every refresh into two.
            session.stack.loopManager.glanceCarbsOnBoard { [weak self] cob in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let changed = cob != self.latestCOB
                    self.latestCOB = cob
                    self.latestCOBAt = Date()

                    if changed { self.refresh(kickMirror: false) }
                }
            }
        }
    }

    /// Logs on change, at most once a minute otherwise, with the ages of both values.
    private func logRender(iob: Double?, cob: Double?, glucoseDate: Date?, now: Date) {
        let key = String(format: "%@|%@", iob.map { String(format: "%.2f", $0) } ?? "nil",
                                          cob.map { String(format: "%.1f", $0) } ?? "nil")
        if key == lastRenderLogKey, let last = lastRenderLogAt, now.timeIntervalSince(last) < 60 { return }
        lastRenderLogKey = key
        lastRenderLogAt = now
        let bgAge = glucoseDate.map { Int(now.timeIntervalSince($0)) }
        let cobAge = latestCOBAt.map { Int(now.timeIntervalSince($0)) }
        SportLog.event("glance", String(format: "RENDER iob=%@ cob=%@ · bgAge=%@ cobCacheAge=%@",
                                        iob.map { String(format: "%.2f", $0) } ?? "nil",
                                        cob.map { String(format: "%.1f", $0) } ?? "nil",
                                        bgAge.map { "\($0)s" } ?? "nil",
                                        cobAge.map { "\($0)s" } ?? "never"))
    }

    /// No loan: the phone's last reading, labelled and dimmed.
    static func idleState(context: WatchContext?, note: String? = nil) -> GlanceUIState {
        var s = GlanceUIState()
        s.phase = .idle
        s.viaPhone = true
        s.bgColor = .dim
        if let quantity = context?.glucose {
            s.bgText = String(format: "%.0f", quantity.doubleValue(for: .milligramsPerDeciliter))
            s.trendSymbol = context?.glucoseTrend?.symbol
        }
        s.loopStatusText = NSLocalizedString("phone loop active", comment: "Glance status when the phone runs the loop")
        s.idleNote = note
        return s
    }

    /// Reaching the phone (open-ended), then taking over the pod (the only determinate bar).
    static func startingState(context: WatchContext?, takingOver: Bool, startedAt: Date?, now: Date) -> GlanceUIState {
        var s = GlanceUIState()
        s.phase = .starting
        s.viaPhone = true
        s.bgColor = .dim
        if let quantity = context?.glucose {
            s.bgText = String(format: "%.0f", quantity.doubleValue(for: .milligramsPerDeciliter))
            s.trendSymbol = context?.glucoseTrend?.symbol
        }
        s.loopStatusText = NSLocalizedString("starting…", comment: "Glance status while starting Sport Mode")
        s.startingStageText = takingOver
            ? NSLocalizedString("taking over pod…", comment: "Glance stage: pod takeover in progress")
            : NSLocalizedString("reaching iPhone…", comment: "Glance stage: waiting for the loan grant")

        s.startedAt = takingOver ? startedAt : nil
        s.g7EtaText = g7EtaText(lastReading: context?.glucoseDate, now: now, firstConnect: true)
        return s
    }

    /// From the G7's 5-minute grid. `firstConnect` suppresses the countdown, which reads as a promise.
    static func g7EtaText(lastReading: Date?, now: Date, firstConnect: Bool = false) -> String? {
        let cadence: TimeInterval = 5 * 60
        guard let last = lastReading, last <= now else {
            return NSLocalizedString("G7 typically within 10 min", comment: "Glance G7 prediction without a prior reading")
        }
        let untilNext = cadence - now.timeIntervalSince(last).truncatingRemainder(dividingBy: cadence)
        if firstConnect {
            return nil
        }
        let seconds = Int(untilNext.rounded())
        guard seconds > 10 else {
            return NSLocalizedString("G7 due about now", comment: "Glance G7 prediction when the next reading is imminent")
        }
        return String(format: NSLocalizedString("G7 in ~%d:%02d", comment: "Glance countdown to the next expected G7 reading (min, sec)"),
                      seconds / 60, seconds % 60)
    }

    /// The ring is the last cycle's `LoopCompletionFreshness`, as on the phone; glucose age is shown
    /// separately. A pure function of its arguments.
    static func activeState(data: WatchLoopManager.GlanceData, cob: Double?, now: Date, phoneGlucoseDate: Date? = nil) -> GlanceUIState {
        var s = GlanceUIState()
        s.overrideLabel = data.overrideLabel
        s.phase = .active

        if let iob = data.iob { s.iobText = String(format: "%.1f", iob) }
        if let cob = cob { s.cobText = String(format: "%.0f", cob) }
        if let rate = data.tempRate {
            s.tempText = String(format: "%+.2f", rate)
        }

        // Judged on arrival stamps, direct first: is the watch standing on its own?
        let within: (Date?) -> Bool = { $0.map { now.timeIntervalSince($0) < displayStaleAge } ?? false }
        if within(data.directG7At) {
            s.bgSource = .directG7
        } else if within(data.phoneRelayAt) {
            s.bgSource = .phoneRelay
        } else {
            s.bgSource = .none
        }

        let age = data.glucoseDate.map { now.timeIntervalSince($0) }
        let isStale = age.map { $0 > displayStaleAge } ?? true

        switch data.lastLoopCompleted.map({ LoopCompletionFreshness(age: now.timeIntervalSince($0)) }) {
        case .fresh?: s.loopFreshness = .fresh
        case .aging?: s.loopFreshness = .aging
        case .stale?: s.loopFreshness = .stale
        case nil:     s.loopFreshness = .unknown
        }
        if let quantity = data.glucose {
            let mgdl = quantity.doubleValue(for: .milligramsPerDeciliter)
            s.bgText = String(format: "%.0f", mgdl)
            if isStale {
                // A stale number keeps its value but loses colour and arrow.
                s.bgColor = .dim
            } else {
                s.trendSymbol = data.trend?.symbol
                let low = data.suspendThreshold?.doubleValue(for: .milligramsPerDeciliter) ?? 70
                s.bgColor = mgdl < low ? .low : (mgdl > 180 ? .high : .inRange)
            }
        }
        if isStale {
            if let age = age {
                s.staleAgeText = String(format: NSLocalizedString("%d min ago — no direct G7", comment: "Glance stale-glucose age line"), Int(age / 60))
            } else {
                s.staleAgeText = NSLocalizedString("no direct G7 reading yet", comment: "Glance line before the first direct reading")
            }

            // Past a missed window the grid predicts nothing.
            let missedAWindow = (age ?? .infinity) > 8 * 60
            s.g7EtaText = g7EtaText(lastReading: data.glucoseDate ?? phoneGlucoseDate, now: now, firstConnect: missedAWindow)

            // The wedge hint outranks the countdown.
            if let hint = G7SilenceHint.text(directAge: data.directG7At.map { now.timeIntervalSince($0) },
                                             relayAge: data.phoneRelayAt.map { now.timeIntervalSince($0) },
                                             sensorAge: data.sensorActivatedAt.map { now.timeIntervalSince($0) }) {
                s.g7EtaText = hint
            }

        // An eventual is only offered against a FRESH reading. A prediction from a stale input is
        // not a weaker prediction, it is a different question.
        } else if let eventual = data.eventual {
            s.eventualText = String(format: "%.0f", eventual.doubleValue(for: .milligramsPerDeciliter))
        }

        // Fresh reading: show provenance; "via iPhone" is drawn in the warning colour.
        if !isStale, let age = age {
            switch s.bgSource {
            case .directG7:
                s.g7EtaText = String(format: NSLocalizedString("G7 direct · %dm", comment: "Glance provenance line for a fresh direct reading (1: minutes ago)"), Int(age / 60))
            case .phoneRelay:
                s.g7EtaText = String(format: NSLocalizedString("via iPhone · %dm", comment: "Glance provenance line when the phone is relaying in a direct-G7 gap (1: minutes ago)"), Int(age / 60))
            case .none:
                break
            }
        }

        s.loopClosed = data.closedLoopEnabled
        // Only worth marking when a CLOSED loop with a fresh reading has still not completed a
        // cycle: an open loop is not expected to, and a stale reading already explains itself.
        if data.closedLoopEnabled, !isStale, let completed = data.lastLoopCompleted {
            s.predictionStale = LoopCompletionFreshness(age: now.timeIntervalSince(completed)) == .stale
        }
        return s
    }
}
