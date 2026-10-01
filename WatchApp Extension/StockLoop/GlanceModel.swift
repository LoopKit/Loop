//
//  GlanceModel.swift
//  WatchApp Extension
//
//  Everything the glance draws, and the rules that turn app state into it. GlanceView renders
//  `GlanceUIState` and decides nothing.
//
//  The page reads MIRRORS. It never synchronously reads the loop's or the loan's queue — the
//  loan queue doubles as the pump's delegate queue, so a read from main blocks the UI for the
//  length of whatever pod operation is in flight. Each refresh asks the owners to republish and
//  then renders the last published values, which is why a number here can be one tick old.
//
//  Two independent clocks run on this page and must not be conflated: the LOOP's freshness
//  (when a cycle last completed, which colours the ring) and the GLUCOSE's age (which dims the
//  number and explains itself in words). One failing does not imply the other.
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
    /// What the page is FOR at this moment, which chooses the whole layout: `.idle` offers Start,
    /// `.starting` shows the takeover's progress, `.active` is the loop's own page, and the two
    /// tail states are the pod going home — `.handingBack` after the watch has stopped dosing,
    /// `.draining` when the phone revoked the loan and only the records are left to return.
    ///
    /// A hand-back that is still DOSING is not one of these: it stays `.active` with
    /// `handbackPending`, because that is the state the user can still back out of.
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

    /// The eventual on screen was computed by a cycle that is now stale. IOB, COB and the running
    /// temp keep updating while the eventual freezes, so it is MARKED rather than hidden: hiding
    /// it would read as "no prediction", which is its own untruth.
    var predictionStale: Bool = false

    /// How old the standing credential is, shown in the start-without-the-phone confirmation.
    /// It is SHOWN and never enforced — staleness is the user's call, and the settings and
    /// history the session would start from are exactly that old.
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

    /// The provenance/countdown line under the centre block. It carries three different things
    /// depending on state: where the current reading came from, when the next one is due, and the
    /// wedge hint. Only one can show, and the hint wins.
    var g7EtaText: String? = nil

    /// A manual bolus the pod has ACCEPTED, with the window it should deliver over.
    var bolusDelivery: (units: Double, startedAt: Date, endsAt: Date)? = nil

    var overrideLabel: String? = nil

    /// A hand-back is draining while the watch keeps dosing. This is the cancellable window, and
    /// it is why the top-right chip becomes Cancel instead of End.
    var handbackPending: Bool = false

    var handbackStartedAt: Date? = nil
}

/// Owns the repaint schedule and builds every frame. Four things can repaint the page, and each
/// covers a failure the others do not: the 2 s tick (time passing while the page is up), the
/// mirror observer (a reading or a cycle landing), the view's notification hooks (a phase or
/// bolus change that must not wait for the tick), and the freshness boundary timer — ageing,
/// which nothing pushes at all.
@MainActor
final class GlanceViewModel: ObservableObject {
    @Published var state = GlanceUIState()

    /// False until the first controller snapshot has been read. `state` starts `.idle`, so
    /// without this gate the page draws "Start Sport Mode" for a moment at every launch — and
    /// during a live loan that reads as "the loan is gone".
    @Published var hasControllerState = false

    /// Read from the controller's NON-BLOCKING mirrors. Both are consulted from main while the
    /// loan queue may be busy with the pod, which is exactly why neither may be a queue read.
    var loanIsLive: Bool {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.isLoanActiveNonBlocking ?? false
    }

    var isResuming: Bool {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.isResumingNonBlocking ?? false
    }

    /// Whether this page should be the one the user lands on. True for every phase except idle:
    /// once a session exists the wrist has a job, and making the user swipe to find it is the
    /// difference between noticing a stalled loop and not.
    var wantsFocus: Bool {
        switch state.phase {
        case .starting, .active, .handingBack, .draining: return true
        case .idle: return false
        }
    }

    /// The on-screen tick. Two seconds is the page's own clock: the elapsed counters, the bolus
    /// bar and the transient notes' expiries all age against it, and none of them are pushed.
    private var timer: Timer?

    /// COB is fetched asynchronously, so the last value is cached and reused until the next one
    /// arrives. `latestCOBAt` records when that was and rides the render log: the screen cannot
    /// show how old the number on it is, and the log has to be able to.
    private var latestCOB: Double?

    private var lastRenderLogAt: Date?
    private var lastRenderLogKey: String?
    private var latestCOBAt: Date?
    private var appStateObservers: [NSObjectProtocol] = []

    /// A preview model holds a hand-written state and reaches nothing: refresh returns at once,
    /// and the actions either do nothing or move the hand-written state so the gallery can show
    /// the resulting frame. That is what lets the previews drive the REAL view with no risk of
    /// one of them requesting a loan or ending a session.
    private let isPreview: Bool

    /// One G7 grid point plus grace. DISPLAY ONLY: past this the number is dimmed and its age is
    /// said out loud, and nothing else changes. The dosing recency gates are separate and stricter
    /// in their own way — do not reuse this constant for anything that licenses a dose.
    private static let displayStaleAge: TimeInterval = 7 * 60

    /// Two fraction digits always, for every insulin volume this page shows. The pod delivers in
    /// 0.05 U pulses, so anything coarser prints a dose the pod cannot give and anything finer
    /// prints precision it does not have.
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

    /// The page's on-screen/off-screen signal comes from the extension delegate, NOT from the
    /// view's lifecycle alone. A screen dim delivers a resign-active, and the undim that follows
    /// delivers no appear at all — so a page driven only by `onAppear`/`onDisappear` stays frozen
    /// on the frame the wrist went down with, for as long as the user keeps glancing at it.
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

    /// Arms the 2 s tick and the standing mirror observer.
    ///
    /// The observer MUST NOT kick the mirror (`kickMirror: false`). A kick republishes the
    /// mirror, the republish posts this very notification, and the coalescing guard on the
    /// publisher has already cleared by the time it posts — so a kicking observer feeds itself
    /// without bound, saturating the loop's queue and main during a loan, which is precisely when
    /// the watch can least afford either.
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

    /// A one-shot repaint at the next freshness boundary — 6 and 16 minutes past the last
    /// completed cycle, matching LoopKit's own fresh/aging/stale cut-offs.
    ///
    /// Ageing pushes NOTHING: if cycles have stopped, no mirror update and no phase change will
    /// ever arrive, so without this the ring sits green straight through both deadlines until
    /// something else happens to rebuild the frame. Re-armed after every refresh, so it always
    /// points at the next boundary rather than a stale one.
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

    /// An off-schedule repaint, for the events that must not wait for the tick: a phase change or
    /// a bolus changing state.
    ///
    /// When the page is not refreshing there is no standing observer, so this arms a one-shot to
    /// catch the mirror publish its own kick provokes — otherwise the frame it draws is the one
    /// from before the event that triggered it.
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

    /// Stops the TICK only. The mirror observer deliberately stays registered: it is cheap, and
    /// it is what repaints a face-up watch the moment a reading or a cycle lands, in the very
    /// lifecycle gaps where no appear/active event is coming.
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

    // Every action below flips the affected field locally, hands the work to the controller, and
    // schedules a refresh a fraction of a second later. The local flip is what makes the tap feel
    // answered; the delay is there because the controller does its work on its own queue and the
    // mirror this page reads is only republished afterwards — an immediate refresh would redraw
    // the state the user just changed.

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

    /// The start gate WARNS and never blocks — every verdict logs its reason and then falls
    /// through to the request.
    ///
    /// Direct G7 only delivers while the app has runtime, so the minutes before a Start tap are
    /// exactly the era in which evidence of a healthy sensor cannot exist: the gate would be
    /// reading the absence of the very runtime the loan is about to grant. "No sensor ever
    /// enrolled" warns for a different reason — a bench rig deliberately running without one is
    /// indistinguishable from a new user, and refusing would block both.
    func startSportMode() {
        RuntimeStateLog.mark("glance.startSportMode")
        guard !isPreview else { return }

        let build = BuildDetails.default.codeIdentity

        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession else {
            let why = ExtensionDelegate.sharedIfAvailable() == nil ? "no app delegate" : "no session"
            SportLog.event("session", "START TAPPED but Sport Mode is unavailable (\(why)) — the stack never assembled · build \(build)")
            return
        }

        switch session.stack.loopManager.sportModeStartGate() {
        case .allowed:
            break
        case .noSensorEverEnrolled:

            SportLog.event("loan", "START with NO SENSOR EVER ENROLLED — loan will run on relayed BG alone and will stop looping if the phone leaves; proceeding (bench rigs look identical from here)")
        case .waitingForFirstReading(let sensorName):

            SportLog.event("loan", "START with sensor \(sensorName) enrolled but no direct reading yet on this watch — proceeding")
        case .noDirectConnection(let sensorName, let silentMinutes):

            SportLog.event("loan", "START with no direct BG from \(sensorName) for \(silentMinutes)m — expected between loans (no runtime, no radio); proceeding, but a relay-only loan stops looping if the phone leaves")
        }
        session.loanController.requestLoan(watchBuild: build)

        // Two snapshots bracket the takeover: one at the tap, one after it should have finished.
        // A takeover that ends with the watch dark is the case that most needs a log on the
        // phone, and by then it cannot send one.
        session.sendLogSnapshot("sport start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) {
            session.sendLogSnapshot("start +35s")
        }
        refresh()
    }

    /// End is not a stop. The watch keeps dosing while its records drain, so the page stays on
    /// the active layout with `handbackPending` set — and stays cancellable — until the phone has
    /// acknowledged them.
    func endSportMode() {
        RuntimeStateLog.mark("glance.endSportMode")
        guard !isPreview else { state.handbackPending = true; return }

        WKInterfaceDevice.current().play(.click)
        state.handbackPending = true

        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.beginHandback()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    /// The only control for the wrist's loop mode, and it goes straight to the watch's own loop
    /// manager. During a loan that mode is the WATCH's: it must never be combined with the
    /// phone's dosing setting, or a phone that happens to be running open loop turns this into a
    /// control the user can tap forever with nothing happening.
    func setLoopClosed(_ closed: Bool) {
        guard !isPreview else {
            state.loopClosed = closed
            state.loopStatusText = closed ? "CLOSED · 0m" : "OPEN"
            return
        }
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.loopManager.setClosedLoopEnabled(closed)
        refresh()
    }

    /// Builds one frame from the loan controller's phase and, when a loan is running, the loop's
    /// glance mirror. The controller's phase is the authority for WHICH page is drawn; the loop
    /// mirror only fills in the numbers.
    ///
    /// `kickMirror` must be false whenever this is called FROM the mirror's own notification —
    /// see `startRefreshing`. The breadcrumbs through the body are not decoration: if main wedges
    /// in here, the last one names which step it wedged in.
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

        switch snap.phase {
        case .idle:

            // The note slot has one occupant. The controller's own note wins over the sensor-code
            // prompt: whatever just happened to a session matters more than a standing setup task.
            var idle = Self.idleState(context: ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext,
                                      note: snap.lastIdleNote ?? G7WatchDirectRead.needsCodeNote)

            if let issued = snap.seizeOfferIssuedAt {
                let f = DateComponentsFormatter()
                f.maximumUnitCount = 1
                f.allowedUnits = [.day, .hour, .minute]
                f.unitsStyle = .abbreviated
                idle.seizeOfferAgeText = f.string(from: Date().timeIntervalSince(issued)) ?? "?"
            }
            state = idle
        // Two controller phases, one UI phase. The user is told which STAGE is running, but the
        // page does not change shape between them — a layout that rearranged itself mid-start
        // would make a slow takeover look like something going wrong.
        case .requested, .takingOver:
            state = Self.startingState(context: ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext,
                                       takingOver: snap.phase == .takingOver,
                                       startedAt: snap.startedAt,
                                       now: Date())
        // The watch has stopped dosing but the pod has NOT moved: it stays assigned here until
        // the phone acknowledges the records. Both notes say so, because a screen implying the
        // pod is already home would invite the user to put the watch down and walk away.
        case .handingBack:
            var s = GlanceUIState(); s.phase = .handingBack

            s.handbackStartedAt = snap.handbackStartedAt

            s.loopStatusText = NSLocalizedString("ending…", comment: "Glance status during hand-back")

            s.phoneUnreachable = !snap.phoneReachable
            s.idleNote = snap.phoneReachable
                ? NSLocalizedString("Waiting for iPhone — pod still on watch. Bolus unavailable until it connects.", comment: "Glance note while a hand-back waits for the phone")
                : NSLocalizedString("Can't reach iPhone — pod still on watch. Move it closer or check its Bluetooth.", comment: "Glance note while a hand-back waits for an UNREACHABLE phone")
            state = s
        // A parked drain is STARTABLE GROUND, not a wall: it draws the ordinary idle page, plus a
        // note that records are still owed to the phone. A watch that rebooted mid-loan must not
        // be left refusing Start until the phone comes back.
        case .recoveredDrain:

            var restIdle = Self.idleState(context: ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext,
                                          note: snap.lastIdleNote
                                            ?? G7WatchDirectRead.needsCodeNote
                                            ?? NSLocalizedString("Records from the last session are waiting for your iPhone. You can still start.",
                                                                 comment: "Glance note while resting on a parked drain"))
            if let issued = snap.seizeOfferIssuedAt {
                let f = DateComponentsFormatter()
                f.maximumUnitCount = 1
                f.allowedUnits = [.day, .hour, .minute]
                f.unitsStyle = .abbreviated
                restIdle.seizeOfferAgeText = f.string(from: Date().timeIntervalSince(issued)) ?? "?"
            }
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
            // The transient line has ONE slot, and these are its claimants in priority order:
            // a hand-back in progress (which is open-ended), then a recent hand-back failure,
            // then a recent start note. The later two carry their own expiry so a message about
            // a moment that has passed stops being shown rather than lingering on a live page.
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

            // Narrate the wait for the pod to accept a manual bolus, and use "starting" until it
            // does — the bolus flow dismisses itself about a second after the tap while the dose
            // can take far longer to reach the pod, and a user reading that silence as a hang
            // taps End, which cancels the in-flight work and destroys the dose.
            //
            // Nothing for the first fraction of a second, so the common fast path still looks
            // instant rather than flashing a message about a wait that did not happen.
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

    /// One RENDER line per distinct (IOB, COB) pair, at most once a minute otherwise. The page
    /// repaints every two seconds, so logging every frame would bury the file; logging on CHANGE
    /// is what makes "the number on the wrist was X at time T" answerable afterwards. The two
    /// ages on the line answer the follow-up: whether X was stale, and whether COB was cached.
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

    /// No loan: the phone owns the pod and this page is a passenger. The glucose shown is the
    /// phone's last relayed reading, labelled and dimmed so it can never be mistaken for a live
    /// wrist reading — this watch has no radio time between loans and its own number would be
    /// arbitrarily old.
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

    /// Between the Start tap and the first cycle. Two stages the user can tell apart: reaching
    /// the phone (open-ended — the phone may be asleep, in a pocket, anywhere) and taking over
    /// the pod (bounded, and the only one that gets a determinate bar).
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

    /// When the next sensor reading is due, from the phase of the G7's own 5-minute grid.
    ///
    /// `firstConnect` suppresses the COUNTDOWN entirely. The prediction is accurate and the first
    /// window is usually caught, but a wall-clock time at the start of a session reads as a
    /// PROMISE — and the few percent that miss it are exactly the moments when the user is
    /// already anxious about whether this is working. The vague phrase for "no prior reading"
    /// survives because it promises nothing.
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

    /// The loop's own page, and the only place the two clocks are resolved.
    ///
    /// The RING is `LoopCompletionFreshness` of the last completed cycle and nothing else — the
    /// same rule the phone uses, so the two devices never disagree about whether the loop is
    /// healthy. Glucose staleness deliberately keeps a separate voice (a dimmed number and a line
    /// saying its age); folding it into the ring would make the wrist stricter than the phone
    /// about a condition the phone shows differently.
    ///
    /// Everything here is a function of the arguments — no app state, and `now` is injected — so
    /// a frame someone saw on their wrist can be reconstructed exactly. Keep it that way.
    static func activeState(data: WatchLoopManager.GlanceData, cob: Double?, now: Date, phoneGlucoseDate: Date? = nil) -> GlanceUIState {
        var s = GlanceUIState()
        s.overrideLabel = data.overrideLabel
        s.phase = .active

        if let iob = data.iob { s.iobText = String(format: "%.1f", iob) }
        if let cob = cob { s.cobText = String(format: "%.0f", cob) }
        if let rate = data.tempRate {
            s.tempText = String(format: "%+.2f", rate)
        }

        // Provenance is judged on the ARRIVAL stamps, direct first: the phone's relay lands a few
        // seconds ahead of the watch's own read of the same sample, so deriving this from the
        // stored row would answer "phone" almost always and never answer the question this line
        // exists for — whether the watch is standing on its own right now.
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
                // A stale number keeps its VALUE and loses its colour and its arrow. Colouring it
                // would assert a range we cannot vouch for, and an arrow is a claim about a trend
                // that stopped being measured; the age line underneath says why.
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

            // Past a whole missed window the grid phase no longer predicts anything worth
            // printing as a countdown, so the estimate is suppressed the same way it is at the
            // start of a session.
            let missedAWindow = (age ?? .infinity) > 8 * 60
            s.g7EtaText = g7EtaText(lastReading: data.glucoseDate ?? phoneGlucoseDate, now: now, firstConnect: missedAWindow)

            // The wedge hint OUTRANKS the countdown: when the watch's Bluetooth is parked there
            // is no next reading to count down to, and telling the user to wait is worse than
            // telling them nothing.
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

        // With a fresh reading the same line carries PROVENANCE instead of a countdown: which
        // device this number came from, and how old it is. "via iPhone" is the one the user needs
        // — it means this watch is not reading the sensor, so walking away from the phone stops
        // the loop — and the view renders it in the warning colour for that reason.
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
