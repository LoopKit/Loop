# Sport Mode: who controls the pod

How Sport Mode decides which device controls the pod, in every situation we know of, and what the looper sees. The
decisions in section 5 are made in one place in code, `LoanControl.decide`, one case per row, each with one test;
section 9 says where. A different answer for one situation is a change to that row, its case and its test.

---

## 1. The world we design for

**On the body, always:** the pod and the sensor. The only exceptions are testing artifacts: the pod emulator on a
counter, an unattached "water pod", the sensor emulator. A sensor off the body is impossible in real use (unlike a
pod, it is useless off the body).

**Usually on the body:** the watch. Exceptions: forgotten, deliberately not worn, charging. A charger by the bed is
normally within the pod's reach; one in another room is not.

**Anywhere:** the phone. In a pocket, on a counter, at home while the looper is out, dead.

**What follows from that.** "Near" for either device means within Bluetooth reach of the body, so of the pod and the
sensor together. A device that can see the sensor can see the pod, and vice versa, except as a testing artifact. A
watch on the wrist is woken by the sensor every five minutes, so it always comes back within a cycle even if watchOS
stops its app; a watch silent for longer than a cycle is off the wrist, dead, or in a test.

**Highly abnormal:** a pod on the body that answers neither device (a dead or faulted pod). Rows 24 and 25 cover it;
in tests it is the pod emulator unplugged.

**One asymmetry that matters for coexistence.** The phone's pod driver holds the pod's connection open whenever the
phone controls the pod and Loop is on screen; the watch connects for each cycle and lets go. So two devices that both
believe they control the pod do not share it: the phone's open connection blocks the watch, and the pod's single
session makes both fail its handshake.

**Values used in the table.** For each device: *near* (within reach of the body; for the watch this includes a
charger within reach), *away*, *dead*. The watch's place is *on wrist*, *off wrist within reach*, or *off wrist out of
reach*.

---

## 2. Principles

In priority order. Rule 1 is a constraint and is never traded. Rules 2 and 3 are the two goals that can conflict;
rule 4 says how.

1. **Insulin is conserved.** No device doses closed loop without every unit the pod delivered being in its records or
   counted conservatively first (booked as a bolus, so dosing errs low). Every row below assumes it; no row says it.
2. **Nobody takes the pod from a device that is looping it.** A tap names which device loops. While that device is
   awake and can reach the pod, only another tap changes that.
3. **Looping conservatively is safer than not looping.** If a device that is there can loop the body, it should.
4. **When 2 and 3 conflict, the known facts decide; when they are unknown, a query does.** They conflict only when
   the other device is silent. The device that could loop queries it. An answer settles it in the other device's
   favour; silence after a direct query counts as "not looping", and looping wins. This is the one place looping
   overrides consent, and it may, because rule 1 makes a wrong guess conservative and the other device's first word
   ends it.
5. **A device that goes off is out of the conversation.** While it is out, the other device may take the pod, after
   querying (rule 4). When it comes back, it cannot know what was decided while it was out, so it queries before
   touching the pod. If the other device holds the pod, it stays out, and the looper starts again by hand. If nothing
   answers, it carries on with what it was last told, because it is the only device there. An inferred takeover is
   not undone when the dead device returns.
6. **The phone looping is the resting state; Sport Mode is entered only by a tap.** Returning to rest may be inferred
   (rule 4). Entering Sport Mode never is. This is why the watch does not take a dead phone's pod: it cannot tell a
   dead phone from one left at home, and in either case it would be starting a mode nobody chose.
7. **Err on the side of telling the looper what is happening.** Whatever a device inferred, it says so. A refusal
   always names the nearest thing that can be done.

**Control changes on evidence, never on a clock.** Evidence is a tap, the other device's word, or an observation
(a pod reading, an answer, silence after a query). Clocks may only decide *when to query* (a report is overdue) and
when to time a notice. The one rule that looks like a clock is the 6-hour limit on a watch resuming, and that is
rule 1: insulin delivered longer ago than its action time cannot be placed.

**A watch's records count as its word too.** This rule exists to tell apart two situations that look alike to the
phone but need opposite answers. In both, a watch turns up holding a loan the phone does not hold.

- *An old loan coming back (row 19).* The watch died mid-loan; the phone, hearing nothing, took the pod back on
  silence and has been looping since. Later the watch revives, still believing in its old loan. The phone must
  refuse: keep the pod and tell the watch to stop. Otherwise a watch with a stale picture of the last hours would
  take over again.
- *A new loan started without the phone (row 17).* The looper left the phone behind and started Sport Mode on the
  watch alone. When the phone comes back, it must adopt that loan and stand aside, because the watch is the one
  looping.

The phone tells them apart by one fact: did the watch's loan start before or after the phone took the pod over?
Before means an old loan coming back; after means a new one. The watch's status report states the loan's start
time. But a revived watch often sends its backlog of records (doses, carbs) before any report, and the records do
not state the start time. If the phone treated those records simply as "a loan is running", it would stand aside
for a stale loan, and its answer would depend on whether the records or the report happened to arrive first.

So records for a loan the phone does not hold are treated as the watch claiming the pod, and they are judged by the
same rule as the report. In place of the start time, they give a limit. A watch logs and sends nothing before its
loan starts, so the loan began no later than its earliest record (or, for a batch with no records, no later than
the moment it was sent). When that limit falls before the phone's takeover, the loan certainly began before it, and
the phone refuses as surely as if it knew the exact start time.

---

## 3. Vocabulary

- **Query:** device to device, "do you hold the pod?". Answered by a message, or by silence after the wait:
  **10 s** while the looper waits on screen (Start, End), **30 s** in the background (every other query), because
  a background question and its answer may each travel queued, and a late answer there moves control wrongly
  (`LoanControl.Wait`). A question and its answer go by the live path when the other device is reachable, and
  queued as well, so a live message lost when an app goes inactive cannot leave the other side unasked or
  unanswered: the stop rides both too. Silence is an answer. The looper never sees a query.
- **Prompt:** device to looper, answered only by a tap. Silence is not an answer: nothing changes until the tap. The
  only prompt the system raises by itself is the offline-start offer ("Start without it?"); every other tap is one
  the looper started.
- **Tell:** device to looper, nothing expected back: a notification, or a message on screen.
- **Actions:** *take* (the phone takes the pod back: reach the pod first, then send the stop, then check insulin),
  *stand aside* (stop controlling, release the radio), *carry on*, *refuse* (decline a tap, keep things as they are),
  *book* (count insulin conservatively, rule 1).
- **Answers a query can get:** silence · "I hold the pod (loan n, started at T)" · "I hold the pod but cannot reach
  it" · "I hold nothing" · a stop (a revoke) for a loan the asker should no longer hold. The last three before the
  stop count as silence for what the asker does next (`LoanControl.afterQuery`).

---

## 4. Warnings: who raises them and where they land

Each row's *Looper sees* cell names the device that raises the warning, whether it is a notification or only on
screen, and the words. Stated once here:

- **Interruption level.** Anything about dosing is time-sensitive; nothing is critical.
- **Where a notification lands is Apple's choice.** A phone notification shows on a worn, unlocked watch when the
  phone is locked; a watch notification shows on the watch only. A Focus mode can silence time-sensitive
  notifications if the looper has not allowed them.
- **On screen** means the Sport Mode page on the watch, or the banner, pod tile and status screen on the phone. It is
  seen only when the looper looks.
- **The phone's copy during a loan.** The phone stores the watch's records as they arrive, so while the watch is in
  reach the phone's stores follow its loop within a cycle; a temp basal still running is stored once it ends. The
  banner says when the records last came. Out of reach, no records is what a loan looks like, and the phone says
  nothing more.

---

## 5. The table

One section per situation, after an index. The inputs describe the world and what each device can see; the result says what happens;
the *why* gives the reasoning, briefly where nothing is in tension and at length where a judgement was made. A
device that is dead shows *dead* in its cells. *Status*: **built**, **deliberate exception** (a principle set aside on
purpose; the *why* says which), **accepted** (nothing can act; Loop without Sport Mode is the same). *Code* names
where the row is decided: `+Name` is the extension file `PodLoanPhoneController+Name.swift` on the phone or
`PodLoanWatchController+Name.swift` on the watch. Every situation with an
acting device is one case of `LoanControl.decide` (`LoopCore/PodLoan/LoanControl.swift`), in this order, with
the row's reason as its comment, and one test in `LoopTests/LoanControlTests.swift`; a different ruling for a situation
is a change to that case and that test.

Each situation lists:
- **Control state:** pod held by · how it got the pod · loan (number, start) · took over on silence at · looper's
  latest tap.
- **Physical configuration:** phone where / alive · watch where / alive.
- **Change:** what changed in the world.
- **Phone sees:** believes · sensor · pod · heard from the watch. **Watch sees:** the same four.
- **Result:** query · answer · action · pod held by afterwards · time without looping · looper sees.
- **Status · Code · Why.**

| # | Situation | Held by afterwards | Status |
|---|---|---|---|
| 1 | [Start, phone near](#1-start-phone-near) | watch, by grant | built |
| 2 | [Start, phone away or dead](#2-start-phone-away-or-dead) | watch, started without the phone | built |
| 3 | [Phone dies, no loan](#3-phone-dies-no-loan) | nobody; the pod runs its schedule within 30 min | deliberate exception for control |
| 4 | [Phone back, no loan](#4-phone-back-no-loan) | phone | built |
| 5 | [Insulin seen, no loan answers](#5-insulin-seen-no-loan-answers) | phone | built |
| 6 | [Message from a closed loan](#6-message-from-a-closed-loan) | phone | built |
| 7 | [End, phone near](#7-end-phone-near) | phone | built |
| 8 | [End, phone away](#8-end-phone-away) | watch | built |
| 9 | [Take Back on the phone](#9-take-back-on-the-phone) | phone | built |
| 10 | [Watch dies, phone near](#10-watch-dies-phone-near) | phone | built |
| 11 | [Watch dies, phone away](#11-watch-dies-phone-away) | nobody; the pod runs its schedule within 30 min | accepted |
| 12 | [Watch back, phone holds the pod](#12-watch-back-phone-holds-the-pod) | phone | built |
| 13 | [Watch back, nobody else holds the pod](#13-watch-back-nobody-else-holds-the-pod) | watch | built |
| 14 | [Watch on a far charger, phone near](#14-watch-on-a-far-charger-phone-near) | phone | built |
| 15 | [Watch out of reach, phone away](#15-watch-out-of-reach-phone-away) | nobody | accepted |
| 16 | [Phone moves during a loan](#16-phone-moves-during-a-loan) | watch | built |
| 17 | [Phone returns, watch started alone and alive](#17-phone-returns-watch-started-alone-and-alive) | watch | built |
| 18 | [Phone returns, watch started alone and dead](#18-phone-returns-watch-started-alone-and-dead) | phone | built |
| 19 | [Watch back after the phone took over](#19-watch-back-after-the-phone-took-over) | phone | built |
| 20 | [Phone returns, watch started alone on a far charger](#20-phone-returns-watch-started-alone-on-a-far-charger) | phone | built |
| 21 | [End, phone away, watch started alone](#21-end-phone-away-watch-started-alone) | watch | built |
| 22 | [Watch started alone dies, phone away](#22-watch-started-alone-dies-phone-away) | nobody | accepted |
| 23 | [Both dead](#23-both-dead) | nobody | accepted |
| 24 | [Start, phone near, pod silent (highly abnormal)](#24-start-phone-near-pod-silent-highly-abnormal) | phone | not built |
| 25 | [Start without the phone, pod silent (highly abnormal)](#25-start-without-the-phone-pod-silent-highly-abnormal) | phone, in name only: nobody loops | built |

### 1. Start, phone near

- **Control state:** pod held by phone (resting state) · loan: none · took over on silence at: none · looper's latest tap: Start on the watch, now
- **Where:** phone near, alive · watch on wrist, alive
- **What changed:** Start tapped on the watch
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: holding, reads · heard from the watch: the Start request
- **Watch sees:** believes the phone holds the pod · sensor: fresh · pod: not touched · heard from the phone: nothing yet
- **Result:** query: the request is the query (watch → phone) → answer: a grant → action: phone releases the pod and holds its dosing; watch takes over (transfer G)
- **Afterwards:** pod held by watch, by grant · time without looping: seconds · looper sees: watch: Sport Mode page; phone: banner "Sport Mode Active"
- **Status:** built · **Code:** phone `+Grant`, watch `+Start`
- **Why:** The looper chose the watch and the phone is there to hand over: the ordinary case. The watch doses from
  its own reading of the sensor, which stock gives it only with the CGM's Read on Apple Watch setting on; with it
  off, the phone refuses the Start and names the setting, rather than turning it on for the looper.

### 2. Start, phone away or dead

- **Control state:** pod held by phone (resting state) · loan: none · took over on silence at: none · looper's latest tap: Start on the watch, now
- **Where:** phone away, or dead · watch on wrist, alive
- **What changed:** Start tapped on the watch
- **Phone sees:** believes it holds the pod (as of when it left), or dead · sensor: none, or dead · pod: out of reach, or dead · heard from the watch: nothing
- **Watch sees:** believes the phone holds the pod · sensor: fresh · pod: not touched · heard from the phone: nothing
- **Result:** query: the request (queued) → answer: silence after 10 s → action: prompt "Start without it?"; on the tap, the watch starts from its stored copy and checks the pod's total first
- **Afterwards:** pod held by watch, started without the phone · time without looping: 10 s plus the tap · looper sees: watch: on screen, the offer
- **Status:** built · **Code:** watch `+Start`, `+Seize`
- **Why:** The looper asked for Sport Mode and the phone cannot grant it. Starting from the stored copy is entering a mode, which needs the looper's tap (rule 6), so the system offers it as the alternative to the refused Start (rule 7). The query's silence decides when to offer, not the reachability flag, which says only whether the phone's app can take a live message this second. A watch not reading the sensor
itself has nothing to dose from, so it offers nothing and says so.

### 3. Phone dies, no loan

- **Control state:** pod held by phone (resting state) · loan: none · took over on silence at: none · looper's latest tap: any
- **Where:** phone dead · watch on wrist, alive
- **What changed:** the phone dies
- **Phone sees:** believes dead · sensor: dead · pod: dead · heard from the watch: dead
- **Watch sees:** believes the phone holds the pod · sensor: fresh · pod: not touched · heard from the phone: nothing; the phone's loop goes stale
- **Result:** query: none → answer: none → action: tell: nobody takes the pod; a pre-scheduled watch warning, pushed out by every word from the phone, fires after 25 min of silence, after the phone's own Loop Failure at 20
- **Afterwards:** pod held by nobody; the pod runs its schedule within 30 min · time without looping: until the looper starts Sport Mode or charges the phone · looper sees: watch · notification (time-sensitive) "Not Hearing From iPhone: your watch hasn't heard from your iPhone for 25 minutes, so it can't tell whether anything is looping. If the iPhone is off or not with you, open Loop on the watch to start Sport Mode." · on screen: the phone's loop ring (red after 16 min, as in Loop) and "Not hearing from iPhone" after 25 min
- **Status:** deliberate exception for control; the warning is built · **Code:** `LoanControl` row 3; watch `NotHearingFromPhoneAlert`
- **Why:** Looping wins under rule 3, but taking the pod here would be entering Sport Mode without a tap, which rule 6 forbids, and the watch cannot tell a dead phone from one left at home. Following rule 3 would start Sport Mode every time the looper walked away from the phone. The cost is Loop's own: away from a working phone, nothing loops. Telling is what remains. The watch knows this state (no loan, no word from the phone), and it is easy to enter without choosing it (a forgotten phone), so it warns once. The phone talks with its loop cycles, so a phone that stops looping goes quiet too; its own pre-scheduled Loop Failure (20 min) reaches the watch when near, or through a cellular watch's relay, so the watch's comes after it, as the backup for a dead phone or a watch with no route to it.

### 4. Phone back, no loan

- **Control state:** pod held by phone (resting state) · loan: none · took over on silence at: none · looper's latest tap: any
- **Where:** phone near again, alive · watch any
- **What changed:** the phone comes back into reach
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: reads it · heard from the watch: nothing
- **Watch sees:** believes the phone holds the pod, or dead · sensor: — · pod: — · heard from the phone: —
- **Result:** query: none → answer: — → action: carry on; the reading's check finds nothing to explain
- **Afterwards:** pod held by phone · time without looping: none beyond the time away · looper sees: nothing
- **Status:** built · **Code:** phone `+Ledger`
- **Why:** The resting state, resumed.

### 5. Insulin seen, no loan answers

- **Control state:** pod held by phone (resting state) · loan: none, as far as the phone knows · took over on silence at: none · looper's latest tap: any
- **Where:** phone near, alive · watch any
- **What changed:** a reading shows the pod delivered more or less than the phone's records explain, beyond 0.20 U
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: reading shows the difference · heard from the watch: nothing
- **Watch sees:** believes idle, or dead · sensor: — · pod: — · heard from the phone: the phone's query
- **Result:** query: phone → watch → answer: silence, or "I hold nothing" → action: book (if more was delivered), keep looping, tell; record the time as "took over on silence"
- **Afterwards:** pod held by phone · time without looping: none · looper sees: phone: notification "Insulin Estimated After Sport Mode: … booked as a bolus" (more delivered) or "Insulin On Board May Be Overstated" (less)
- **Status:** built · **Code:** phone `+Ledger` `followAnotherControllersInsulin`
- **Why:** The phone already holds the pod, so silence keeps it there. A real loan answers (rows 17, 18); no answer means either a watch that started alone and died (row 18) or, without a loan, an uncertain-delivery bolus or a testing artifact. Booking covers all three conservatively.

### 6. Message from a closed loan

- **Control state:** pod held by phone (any) · loan: the phone has ended loan n · took over on silence at: any · looper's latest tap: any
- **Where:** phone near, alive · watch near, alive
- **What changed:** a message arrives from the watch about loan n
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: holding · heard from the watch: a report, records or an offer for loan n
- **Watch sees:** believes it holds loan n · sensor: fresh · pod: trying · heard from the phone: nothing
- **Result:** query: none → answer: — → action: send the stop for loan n again (at most every 20 s)
- **Afterwards:** pod held by phone · time without looping: none · looper sees: watch: "Sport Mode ended. Your iPhone has the pod"
- **Status:** built · **Code:** phone `+Mirror` `resendRevokeForClosedSession`
- **Why:** The watch missed the stop; it gets it again.

### 7. End, phone near

- **Control state:** pod held by watch (grant) · loan: n · took over on silence at: none · looper's latest tap: End on the watch, now
- **Where:** phone near, alive · watch on wrist, alive
- **What changed:** End tapped on the watch
- **Phone sees:** believes the watch holds loan n · sensor: fresh · pod: released · heard from the watch: the hand-back offer
- **Watch sees:** believes it holds loan n · sensor: fresh · pod: holding · heard from the phone: an acknowledgement
- **Result:** query: the offer is the query (watch → phone) → answer: acknowledged → action: hand back (transfer H)
- **Afterwards:** pod held by phone · time without looping: seconds · looper sees: watch: "returning records…", then the phone's page; phone: banner gone
- **Status:** built · **Code:** watch `+Handback`, phone `+Records`
- **Why:** The looper's latest decision, and both devices are there to carry it out.

### 8. End, phone away

- **Control state:** pod held by watch (grant) · loan: n · took over on silence at: none · looper's latest tap: End on the watch, now
- **Where:** phone away, or dead · watch on wrist, alive
- **What changed:** End tapped on the watch
- **Phone sees:** believes the watch holds loan n, or dead · sensor: none, or dead · pod: out of reach · heard from the watch: nothing
- **Watch sees:** believes it holds loan n · sensor: fresh · pod: holding · heard from the phone: nothing
- **Result:** query: the offer (queued) → answer: silence after 10 s → action: refuse the End; the loan continues
- **Afterwards:** pod held by watch · time without looping: none · looper sees: watch: on screen, not a notification: "iPhone isn't nearby, so the pod can't be handed back. Sport Mode keeps looping. To stop automatic dosing, open the loop on the watch."
- **Status:** built · **Code:** watch `+Handback`
- **Why:** This refuses the looper's express intent, and the reason has to be honest. End names an action, giving the pod to the phone, which cannot be done without the phone. What the looper meant is one of two things the watch cannot tell apart: end Sport Mode (impossible here) or stop dosing (possible, by opening the loop). So the refusal says both. How the watch knows the phone is away: it sends the offer and waits, like every other query. The reachability flag reports only whether the phone's app can take a live message this second, and would refuse with the phone in the next room. An offer that lands late only stores records; nothing changes hands.

### 9. Take Back on the phone

- **Control state:** pod held by watch (grant, or started alone and adopted) · loan: n · took over on silence at: none · looper's latest tap: Take Back on the phone, now
- **Where:** phone near, alive · watch on wrist, alive or dead
- **What changed:** Take Back tapped
- **Phone sees:** believes the watch holds loan n · sensor: fresh · pod: released · heard from the watch: anything
- **Watch sees:** believes it holds loan n, or dead · sensor: fresh, or dead · pod: holding, or dead · heard from the phone: the stop
- **Result:** query: none: a tap needs no query → answer: — → action: take (reach the pod in 5 s, send the stop, check insulin; if the pod does not answer, refuse: transfer T)
- **Afterwards:** pod held by phone · time without looping: seconds · looper sees: phone: banner gone; watch: "Sport Mode ended. Your iPhone has the pod"
- **Status:** built · **Code:** phone `+Reclaim`
- **Why:** A tap is the looper's latest decision.

### 10. Watch dies, phone near

- **Control state:** pod held by watch (grant) · loan: n · took over on silence at: none · looper's latest tap: Start on the watch, earlier
- **Where:** phone near, alive · watch on wrist, dead
- **What changed:** the watch dies
- **Phone sees:** believes the watch holds loan n · sensor: fresh · pod: released · heard from the watch: nothing for more than a cycle
- **Watch sees:** believes dead · sensor: dead · pod: dead · heard from the phone: dead
- **Result:** query: phone → watch, once the report is overdue → answer: silence after 30 s → action: take; record the time as "took over on silence"
- **Afterwards:** pod held by phone · time without looping: 6–11 min, then 30 s · looper sees: phone: notification "Watch Not Looping: this iPhone is taking the pod back; insulin the watch gave is counted"
- **Status:** built · **Code:** phone `+Hold`
- **Why:** A live watch on the wrist, with the body in reach, answers within seconds. Silence means it is not looping, and looping conservatively is safer than not looping. The watch's first word would end a mistake. When it comes back: row 12.

### 11. Watch dies, phone away

- **Control state:** pod held by watch (grant) · loan: n · took over on silence at: none · looper's latest tap: Start on the watch, earlier
- **Where:** phone away, or dead · watch on wrist, dead
- **What changed:** the watch dies
- **Phone sees:** believes the watch holds loan n, or dead · sensor: none · pod: out of reach · heard from the watch: nothing
- **Watch sees:** believes dead · sensor: dead · pod: dead · heard from the phone: dead
- **Result:** query: none: no device can see the body → answer: — → action: nothing
- **Afterwards:** pod held by nobody; the pod runs its schedule within 30 min · time without looping: until a device is back (rows 12, 13, 18) · looper sees: nothing
- **Status:** accepted · **Code:** —
- **Why:** Nobody can act. Loop with a dead phone is the same.

### 12. Watch back, phone holds the pod

- **Control state:** pod held by phone (took back by tap, or took over on silence) · loan: n (closed) · took over on silence at: none, or when the phone took over · looper's latest tap: Start on the watch, earlier; or Take Back
- **Where:** phone near, alive · watch on wrist, back from dead
- **What changed:** the watch comes back
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: holding · heard from the watch: "I hold loan n" (the watch's query)
- **Watch sees:** believes it holds loan n, as of when it died · sensor: fresh · pod: not touched · heard from the phone: nothing at launch
- **Result:** query: watch → phone, once its link has started; live when the phone is reachable, and queued → answer: the stop for loan n → action: stand aside, before any dose
- **Afterwards:** pod held by phone · time without looping: none · looper sees: watch: "Checking with your iPhone…" while it asks, then "Sport Mode ended. Your iPhone has the pod"
- **Status:** built · **Code:** watch `+Resume`, phone `+Mirror`
- **Why:** The watch was out of the conversation (rule 5); the phone holds the pod; the watch stays out and the looper starts again if wanted. The question waits for the watch's link to the phone to start: a message sent before that is lost. It goes by the live path when the phone is reachable, and queued as well; queued alone, the answer can take longer than the wait, and the watch would loop beside the phone until it arrived. The watch shows that it is checking, and builds nothing that can reach the pod until the check ends.

### 13. Watch back, nobody else holds the pod

- **Control state:** pod held by watch (grant, or started alone) · loan: n · took over on silence at: none · looper's latest tap: Start on the watch, earlier
- **Where:** phone away or dead; or near and still lending · watch on wrist, back from dead
- **What changed:** the watch comes back
- **Phone sees:** believes the watch holds loan n, or dead · sensor: — · pod: released, or out of reach · heard from the watch: "I hold loan n", or nothing
- **Watch sees:** believes it holds loan n · sensor: fresh · pod: not touched · heard from the phone: nothing
- **Result:** query: watch → phone → answer: silence (phone away), or nothing back (phone still lending) → action: carry on: the loop gets the pod; its first reading closes the window from the last reading before it died, booking what its records cannot explain
- **Afterwards:** pod held by watch · time without looping: 30 s plus the first reading · looper sees: watch: "Checking with your iPhone…" for up to 30 s, then a note if anything was booked: "0.55 U the watch had no record of, counted as insulin on board"
- **Status:** built · **Code:** watch `+Resume`, `+Seize`
- **Why:** The only device there carries on with what it was last told (rule 5). More than 6 hours off: no resume, records go home, "Sport Mode Ended" (rule 1).

### 14. Watch on a far charger, phone near

- **Control state:** pod held by watch (grant) · loan: n · took over on silence at: none · looper's latest tap: Start on the watch, earlier
- **Where:** phone near, alive · watch off wrist out of reach, alive
- **What changed:** the watch goes on a charger out of the pod's reach
- **Phone sees:** believes the watch holds loan n · sensor: fresh · pod: released · heard from the watch: nothing for more than a cycle (a cycle that cannot reach the pod sends no report)
- **Watch sees:** believes it holds loan n · sensor: none · pod: unreachable · heard from the phone: the phone's query
- **Result:** query: phone → watch → answer: "I hold loan n but cannot reach the pod" → action: take, as on silence; record the time
- **Afterwards:** pod held by phone · time without looping: 6–11 min, then 30 s · looper sees: phone: notification "Watch Not Looping: this iPhone is taking the pod back…"; watch: on screen "Sport Mode ended. Your iPhone has the pod"
- **Status:** built · **Code:** phone `+Hold`, watch `+Handback` (the answer)
- **Why:** Rule 2 protects a device that is looping. This one holds the loan and cannot act on it. It is alive and answers, so silence cannot be the signal; the answer carries the fact, and "cannot reach" is acted on like silence. The watch could give up the pod by itself after a failed cycle, but it cannot tell whether the phone is there to take it, and giving up with nobody there gains nothing. The phone knows it is near and can loop, so the phone decides. Rare: a charger by the bed is within reach.

### 15. Watch out of reach, phone away

- **Control state:** pod held by watch (grant) · loan: n · took over on silence at: none · looper's latest tap: Start on the watch, earlier
- **Where:** phone away, or dead · watch off wrist out of reach, alive
- **What changed:** both away from the body
- **Phone sees:** believes the watch holds loan n, or dead · sensor: none · pod: out of reach · heard from the watch: nothing
- **Watch sees:** believes it holds loan n · sensor: none · pod: unreachable · heard from the phone: nothing
- **Result:** query: none → answer: — → action: nothing; the watch's own "not looping" warnings
- **Afterwards:** pod held by nobody · time without looping: until a device is back · looper sees: watch: notifications "Loop hasn't completed" at 20 and 40 min, 1 and 2 h, on a watch nobody is wearing
- **Status:** accepted · **Code:** watch `LoopStallWatchdog`
- **Why:** Nobody can act; the warnings land on the watch, which is not worn.

### 16. Phone moves during a loan

- **Control state:** pod held by watch (grant) · loan: n · took over on silence at: none · looper's latest tap: Start on the watch, earlier
- **Where:** phone leaves, dies, or comes back · watch on wrist, alive
- **What changed:** the phone changes place or state
- **Phone sees:** believes the watch holds loan n · sensor: any · pod: released · heard from the watch: reports each cycle
- **Watch sees:** believes it holds loan n · sensor: fresh · pod: holding · heard from the phone: anything
- **Result:** query: none → answer: — → action: carry on
- **Afterwards:** pod held by watch · time without looping: none · looper sees: phone: banner "Sport Mode Active" when looked at
- **Status:** built · **Code:** —
- **Why:** The latest decision stands; nothing about the phone changes it.

### 17. Phone returns, watch started alone and alive

- **Control state:** pod held by watch (started without the phone) · loan: n, started at T · took over on silence at: none · looper's latest tap: Start Anyway on the watch, earlier
- **Where:** phone near again, alive · watch on wrist, alive
- **What changed:** the phone comes back
- **Phone sees:** believes it holds the pod (it was never told) · sensor: fresh · pod: reads it: insulin it cannot explain · heard from the watch: "I hold loan n" (on reach), or nothing yet
- **Watch sees:** believes it holds loan n · sensor: fresh · pod: holding · heard from the phone: anything
- **Result:** query: phone → watch, on seeing the insulin; or none, if the watch's word came first → answer: "I hold loan n" → action: stand aside, adopt the loan; from here rows 7–16 apply
- **Afterwards:** pod held by watch · time without looping: none · looper sees: phone: banner "Sport Mode Active" (no prompt, no notification)
- **Status:** built · **Code:** phone `+Mirror`, `+Ledger`
- **Why:** The latest decision was the looper's Start on the watch, made without the phone; the phone's return is not a decision, so it raises no prompt.

### 18. Phone returns, watch started alone and dead

- **Control state:** pod held by watch (dead) (started without the phone) · loan: n, started at T · took over on silence at: none · looper's latest tap: Start Anyway on the watch, earlier
- **Where:** phone near again, alive · watch on wrist, dead
- **What changed:** the phone comes back
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: insulin it cannot explain · heard from the watch: nothing
- **Watch sees:** believes dead · sensor: dead · pod: dead · heard from the phone: dead
- **Result:** query: phone → watch → answer: silence → action: book what it cannot explain, keep looping, tell; record the time as "took over on silence"
- **Afterwards:** pod held by phone · time without looping: none (the phone was already looping when it read) · looper sees: phone: notification "Insulin Estimated After Sport Mode: Sport Mode probably started away from the phone: … booked as a bolus"
- **Status:** built · **Code:** phone `+Ledger`
- **Why:** The watch is out of the conversation; the phone holds the pod and keeps it. When the watch comes back: row 19.

### 19. Watch back after the phone took over

- **Control state:** pod held by phone (took over on silence (row 18, or row 10/14)) · loan: n, started at T1 · took over on silence at: T2, after T1 · looper's latest tap: Start Anyway on the watch, at T1
- **Where:** phone near, alive · watch on wrist, back from dead
- **What changed:** the watch comes back
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: holding · heard from the watch: "I hold loan n, started at T1"
- **Watch sees:** believes it holds loan n, as of when it died · sensor: fresh · pod: not touched · heard from the phone: nothing at launch
- **Result:** query: watch → phone → answer: the stop for loan n → action: stand aside, before any dose
- **Afterwards:** pod held by phone · time without looping: none · looper sees: watch: "Checking with your iPhone…" while it asks, then "Sport Mode ended. Your iPhone has the pod"
- **Status:** built · **Code:** phone `+Mirror` (`refusesRevivedLoan`)
- **Why:** Two rules meet. A watch's word normally makes the phone stand aside (rule 2), because a watch that says it holds a loan is usually looping it. But this watch was out of the conversation: the phone queried, got nothing, and has looped since. Its claim is about the time before it died. Standing aside would move control, silently, to a device the looper stopped using, reversing the takeover without a tap (rule 5). The phone tells the cases apart by one fact it holds, when it took over: a loan started before that is a revived claim, refused; one started after is a fresh Start the looper made while the phone was away, honoured (row 17). Accepted cost: if the watch was merely slow to answer, the takeover was a mistake and this keeps it; one tap restores the loan, and the watch says what happened.

### 20. Phone returns, watch started alone on a far charger

- **Control state:** pod held by watch (started without the phone) · loan: n · took over on silence at: none · looper's latest tap: Start Anyway on the watch, earlier
- **Where:** phone near again, alive · watch off wrist out of reach, alive
- **What changed:** the phone comes back
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: insulin it cannot explain · heard from the watch: nothing
- **Watch sees:** believes it holds loan n · sensor: none · pod: unreachable · heard from the phone: the phone's query
- **Result:** query: phone → watch → answer: "I hold loan n but cannot reach the pod" → action: as on silence: book, keep looping, tell; record the time
- **Afterwards:** pod held by phone · time without looping: none · looper sees: as row 18
- **Status:** built · **Code:** phone `+Ledger`, `+Hold`
- **Why:** As row 14: a holder that cannot reach the pod is treated as absent. When the watch is back in reach it queries and gets the stop (row 19).

### 21. End, phone away, watch started alone

- **Control state:** pod held by watch (started without the phone) · loan: n · took over on silence at: none · looper's latest tap: End on the watch, now
- **Where:** phone away, or dead · watch on wrist, alive
- **What changed:** End tapped
- **Phone sees:** believes the phone holds the pod (never told), or dead · sensor: — · pod: out of reach · heard from the watch: nothing
- **Watch sees:** believes it holds loan n · sensor: fresh · pod: holding · heard from the phone: nothing
- **Result:** query: the offer (queued) → answer: silence after 10 s → action: refuse, as row 8
- **Afterwards:** pod held by watch · time without looping: none · looper sees: as row 8
- **Status:** built · **Code:** watch `+Handback`
- **Why:** As row 8.

### 22. Watch started alone dies, phone away

- **Control state:** pod held by watch (dead) (started without the phone) · loan: n · took over on silence at: none · looper's latest tap: Start Anyway on the watch, earlier
- **Where:** phone away, or dead · watch on wrist, dead
- **What changed:** the watch dies
- **Phone sees:** believes the phone holds the pod (never told), or dead · sensor: none · pod: out of reach · heard from the watch: nothing
- **Watch sees:** believes dead · sensor: dead · pod: dead · heard from the phone: dead
- **Result:** query: none → answer: — → action: nothing
- **Afterwards:** pod held by nobody · time without looping: until rows 13 or 18 · looper sees: nothing
- **Status:** accepted · **Code:** —
- **Why:** Nobody can act.

### 23. Both dead

- **Control state:** pod held by whoever held it (any) · loan: any · took over on silence at: any · looper's latest tap: any
- **Where:** phone dead · watch dead
- **What changed:** both die
- **Phone sees:** believes dead · sensor: dead · pod: dead · heard from the watch: dead
- **Watch sees:** believes dead · sensor: dead · pod: dead · heard from the phone: dead
- **Result:** query: none → answer: — → action: nothing; the pod runs its schedule
- **Afterwards:** pod held by nobody · time without looping: until a device is back · looper sees: nothing
- **Status:** accepted · **Code:** —
- **Why:** Nothing to decide.

### 24. Start, phone near, pod silent (highly abnormal)

- **Control state:** pod held by phone (resting state) · loan: none · took over on silence at: none · looper's latest tap: Start on the watch, now
- **Where:** phone near, alive · watch on wrist, alive
- **What changed:** Start tapped on the watch
- **Phone sees:** believes it holds the pod · sensor: fresh · pod: holding, no answer · heard from the watch: the Start request
- **Watch sees:** believes the phone holds the pod · sensor: fresh · pod: not touched · heard from the phone: nothing yet
- **Result:** query: the request is the query (watch → phone) → answer: a refusal, within the watch's 10 s wait → action: phone keeps the pod; watch shows "The iPhone couldn't reach the pod and kept it. Try again."
- **Afterwards:** pod held by phone · time without looping: as long as the pod is silent, as in Loop without Sport Mode · looper sees: watch: the refusal on screen; phone: Loop's own pod-communication warnings
- **Status:** not built: the phone waits on the pod past the 10 s, so the watch reads silence and offers row 2's start without the phone · **Code:** phone `+Grant`
- **Why:** **Highly abnormal.** A device near the body reaches the pod unless the pod itself fails (a dead or faulted pod; in tests, the emulator unplugged). The phone is there, so its answer must arrive inside the wait: its silence would say it is away, and starting without it cannot help when the pod is the problem.

### 25. Start without the phone, pod silent (highly abnormal)

- **Control state:** pod held by phone (resting state) · loan: none · took over on silence at: none · looper's latest tap: Start Anyway on the watch, now
- **Where:** phone away, or dead · watch on wrist, alive
- **What changed:** Start Anyway tapped
- **Phone sees:** believes it holds the pod (as of when it left), or dead · sensor: none, or dead · pod: out of reach, or dead · heard from the watch: nothing
- **Watch sees:** believes the phone holds the pod · sensor: fresh · pod: trying, no answer · heard from the phone: nothing
- **Result:** query: none: the pod read is the check → answer: no pod answer within the 60 s takeover window → action: watch gives up and returns to rest
- **Afterwards:** pod held by phone, in name only: nobody loops · time without looping: until the pod answers or is replaced · looper sees: watch: on screen "The pod didn't answer, so Sport Mode didn't start. Neither device is looping."
- **Status:** built · **Code:** watch `+Start`, `+Seize`
- **Why:** **Highly abnormal.** The phone at home and a dead or faulted pod (watch Bluetooth off has its own warnings; a pocket that blocks radio is not realistic). In tests: the emulator unplugged with the phone's radios off. Nobody can loop, so the looper needs to learn that the pod is the problem.


**Physically impossible (no behaviour, at most a log line):** the sensor away from the body; a device that can see
the sensor but not the pod, or the pod but not the sensor.

**Possible only as testing artifacts (logged, no warning built):** see section 7.

---

## 6. Transfers

The table above describes *holding*. A transfer is the pod moving between holders: a short conversation with fixed
steps, where what goes wrong is always a step's message not arriving. One rule covers them: **a transfer that does
not complete goes back to the state before it began, or to the resting state if that cannot be established.**

**Nobody takes the pod while it is giving a bolus.** The pod gives a bolus by itself, at a fixed rate, once it has
accepted it, so a pod handed over mid-bolus would leave the record wrong on both sides. A Start while the phone's
own bolus runs, and an End or a Take Back while the watch's runs, are refused with how long the bolus has left; the
looper tries again after it. A bolus counts from the moment it is sent until it has finished or been cancelled, and
the watch checks again when it would release the pod. The mirror holds too: nobody starts a bolus while the pod is
being handed back; with an End waiting, a bolus asked for on the watch is refused, and the looper boluses from the
iPhone once it has the pod. The
phone stores a watch bolus still being given at once, as a bolus in progress (mutable, as Loop's own drivers report
one), and the finished record replaces it. A take-over on silence, where nobody can retry, waits for the pod to finish the bolus
it reports. The pod has one connection, so the device reading it cannot be raced by a new bolus. An offline Start
cannot ask the phone and takes the pod whatever it is giving: the phone's records are trued up from the pod's
delivered total when it is back with the pod.

**Nor while a command to it is unconfirmed.** A command the pod has not confirmed (its answer lost, or still being
sent) can be settled only by the device that sent it, and the copy of the pump's state handed over leaves it out.
The pod driver keeps the pod while one is open: a Start or an End is refused with "The pod hasn't confirmed the last
command yet. Try again in a minute.", and the device keeps looping, which settles the command at its next exchange
with the pod. Where the driver is not asked, §8 says what happens.

| Transfer | Step that fails | Who notices | What it sees | What it does | Pod held by | Looper sees | Status |
|---|---|---|---|---|---|---|---|
| **G** grant (phone → watch) | the request is lost | watch | silence 10 s after the request | prompt "Start without it?" if it has a stored copy, else "No response from iPhone" | phone | watch: on screen | built |
| G | the grant is lost or the takeover stalls | phone | no confirmation 20 s after the grant | query the watch | nobody (the phone has released; the watch has not taken) | — | built |
| G | ″ | phone | answer "I know no such grant" | take back at once | phone | phone: notification "The watch didn't take the pod. This phone kept it." | built |
| G | ″ | phone | silence 30 s after that query | take back | phone | ″ | built |
| G | ″ | phone | answer "taking over" | wait until the grant's lease ends (60 s), then query once more and take back on silence | the watch if it lands | ″ if it does not | built |
| G | the phone's own bolus is still being given at the Start | phone | its pump's bolus state | deny the Start: "A bolus is still being given. Try again in N seconds." | phone | watch: on screen, the reason, with a haptic | built |
| G | a command to the pod is unconfirmed at the Start | phone | its pod driver keeps the pod when asked to let it go | deny the Start: "The pod hasn't confirmed the last command yet. Try again in a minute."; the phone loops again | phone | watch: on screen, the reason, with a haptic | built |
| G | the takeover fails on the watch | watch, then phone | the watch reports failure | the phone takes back at once | phone | watch: on screen, the reason | built |
| G | the looper cancels at the offline offer, and the grant arrives after that | watch | a grant for a Start no longer wanted | answer "takeover failed": Sport Mode is entered only by a tap, and the cancel withdrew it; a new Start asks afresh | phone | phone: takes the pod back at once, as above | built |
| G | the grant is numbered at or below a loan the watch already knows | watch | a stale grant | answer "takeover failed" | phone | — | built |
| G | the confirmation is lost | phone | the query is answered "I hold loan n" | treat the takeover as complete | watch | — | built |
| **S** offline start | the pod does not answer within the lease | watch | no pod reading | back to rest | phone (as before) | watch: "Sport Mode start expired before the pod answered" | built |
| **H** hand-back (watch → phone) | the watch's bolus is still being given at End | watch | its pump's bolus state | refuse the End: "A bolus is still being given. Try again in N seconds."; the loan continues | watch | watch: on screen over the bolus progress, with a haptic | built |
| H | a command to the pod is unconfirmed once dosing has stopped at End | watch | its pod driver keeps the pod when asked to let it go | refuse the End: "The pod hasn't confirmed the last command yet. Try again in a minute."; the watch loops again | watch | watch: on screen, with a haptic | built |
| H | the phone is away at End | watch | silence 10 s after the offer | refuse (row 8) | watch | row 8 | built |
| H | the phone acknowledged the first offer, later offers go unanswered | watch | no acknowledgement; resends every 15 s | keep resending, by every path, for the 2-min budget | watch, still looping | watch: "ending…" | built |
| H | the final offer (sent after dosing stopped) is not acknowledged within the budget | watch | no acknowledgement | let the pod go and keep sending records; the phone takes the pod when they land, or when its overdue query is answered "I hold nothing" (counted as silence) | nobody until the phone takes it (seconds, or 6–11 min if every message was lost) | watch: notification "End Not Confirmed: the watch has stopped dosing… open Loop on the iPhone and tap the pod tile" | built. The transfer rule's second half: the watch cannot tell whether its final offer arrived, and resuming would dose beside a phone that may already be taking the pod, so the resting state it is |
| **T** take-back (phone ← watch's pod) | the pod does not answer within 5 s | phone | no link | refuse; the loan is unchanged | watch | phone: "Couldn't Reach the Pod" | built |
| T | the pod is giving the watch's bolus when the phone reaches it | phone | the pod's status, read before the stop | a tapped take-back is refused: "A bolus is still being given. Try again in N seconds."; a take-over on silence waits for the pod to finish, its link limit starting again after | watch, until the bolus ends | phone: notification "Wait for the Bolus" (tap); nothing (silence) | built |
| T | the stop is lost (watch off) | watch, at return | its query is answered with a stop | stand aside (row 12) | phone | row 12 | built |
| T | the pod is not reached within 12 s of a take-back | phone | link still down | the pod driver searches for the pod by its advertisement, until the pod answers or control is released; connects then go back to the phone's own handle | phone | — | built |
| T | the pod cannot be read after the take-back | phone | the insulin check is owed | hold dosing until the pod answers, then check | phone, not dosing | — | built |

---

## 7. Testing artifacts

Failures only a test can produce. They are logged when recognised; no warning is built for them.

- **Pod emulator on a counter, devices carried away.** The watch gets no sensor or pod wakes, watchOS stops its app,
  it goes silent, and a phone back near the counter takes the pod (row 10 by mistake).
- **Pod emulator not delivering or not reachable** (as a real pod that answers no one: rows 24 and 25). The pod's total does not move while the records expect basal, so
  the hand-back check reports insulin overstated, and the phone's reconnect may need its escalation.
- **Pod emulator needs a reboot** after some failed takeovers.
- **Water pod** off the body: as the emulator on a counter.
- **Sensor emulator out of reach** while the pod is reachable: the watch's cycles refuse for lack of glucose; the
  phone's "near the body" test fails, so it never queries.

---

## 8. Known limits and open questions

- **The watch reads the sensor in its own slot, which Dexcom's watch app also uses.** Read on Apple Watch and
  Dexcom's watch app together are expected to collide, so they are not supported together (untested). The Dexcom
  app on the phone is unaffected.

- **An unconfirmed command where the pod driver is not asked.** The driver refuses to let the pod go at a Start or
  an End (§6), but two cases never ask it. In both the command's own record is lost, and the insulin check counts
  what the pod delivered beyond the records as a bolus, so dosing errs low.
  - *The stored copy for a Start without the phone.* The phone refreshes the watch's copy of the pump while it loops;
    a refresh made while a command is unconfirmed leaves the command out, and a Start from that copy does not know
    it. The watch's takeover check books the difference.
  - *A device told to stand aside while it holds an unconfirmed command.* The watch drops its pod driver when it
    stands aside, so its command goes nowhere. The phone keeps its driver: told of a loan the watch started without
    it (row 17) while a command is unconfirmed, its driver keeps the pod. The phone stands aside all the same: it
    doses nothing while the watch loops, and reads the pod at once, since a phone standing aside runs no loop cycle
    that would. The pod shows that the watch has run it, so the driver drops the command with nothing booked and
    lets go; the insulin check books anything the pod gave. If that read fails, the driver lets go after the
    phone's next exchange with the pod, which nothing schedules; until then the phone may reach for the pod beside
    the watch.
- **Row 15's warnings land on a watch nobody is wearing.** Nothing better is possible without the phone.
- **A stop queued to a watch that is off** may be lost, or delivered once the watch's link to the phone has started.
  Row 12 does not depend on it: the returning watch asks.
- **A watch relaunched before its first unlock** opens its stores late. Messages that arrive meanwhile are held and
  replayed; nothing doses in that time.
- **A take-back by tap tells nothing on the phone**, since the looper did it; the watch says "Sport Mode ended. Your
  iPhone has the pod" when next looked at.
- **The phone's Loop Failure and a watch left with the looper.** It reaches the watch through a cellular watch's
  relay; a watch without cellular gets nothing from a phone out of reach, and a dead phone fires nothing either way.
  Row 3's watch warning covers both.
- **Open: telling the phone over the internet.** A watch that starts Sport Mode without the phone could tell it over
  cellular or the internet, so a phone left at home knows about the loan before it returns (row 17). Not investigated.

---

## 9. Where the decisions live in code

- **`LoopCore/PodLoan/LoanControl.swift`**: the decisions of section 5 as one function, `LoanControl.decide`. Its
  inputs are the control state and what the acting device can see (the physical configuration is not an input: no
  device can know it); its output is the decision (query, then what silence means; take; stand aside; send the stop;
  refuse; prompt; tell). One case per row, in this document's order, each commented with the row's reason;
  `afterQuery` holds the one rule for answers (silence, or "cannot reach the pod", means the `onSilence` branch); the
  two waits and the overdue threshold sit beside it.
- **`LoopTests/LoanControlTests.swift`**: one test per row, set up from the row's scenario.
- **Phone**, `PodLoanPhoneController+Hold.swift`: describes the situation (`controlSituation`), calls the function
  (`decideAndAct`) and carries out the decision (`carryOut`), including the query (`askWatch`). The decision points
  that call it: a pod reading (`+Ledger`), the watch's report overdue (`+Hold`), the watch's claims in status reports
  (`+Mirror`) and records (`+Records`), the Take Back tap.
- **Watch**: the Start (`+Start`), the End (`+Handback`), the return from off (`+Resume`) and every word from the phone
  while no loan runs (row 3, `notePhoneHeard`) each call the function and carry out the result.
- **Transfers** (section 6) decide inside their own code: the grant and its probe (`+Mirror`, `+Grant`), the
  hand-back (`+Handback`, `+Records`), the take-back (`+Reclaim`, `+Settle`). This is deliberate. A transfer is a
  short conversation with steps, timers and retries, not a single decision, and every failed step follows the one
  transfer rule; what differs between them is timing. A different outcome for one transfer would move that
  transfer's choice into `LoanControl`, with its test.
