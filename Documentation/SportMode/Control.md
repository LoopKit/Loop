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

**A watch's records are its word too.** Records from a loan the phone does not hold are a claim to it, judged like
the watch's own report, so arrival order cannot change the outcome. The report says when the loan started; records
bound it, since nothing is logged or sent before a loan starts: their first record, or their send time, is the
latest it could have started, and a bound before the takeover is as sure as the time.

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

---

## 5. The table

One row per situation. The inputs describe the world and what each device can see; the result says what happens;
the *why* gives the reasoning, briefly where nothing is in tension and at length where a judgement was made. A
device that is dead shows *dead* in its cells. *Status*: **built**, **deliberate exception** (a principle set aside on
purpose; the *why* says which), **accepted** (nothing can act; Loop without Sport Mode is the same). *Code* names
where the row is decided: `+Name` is the extension file `PodLoanPhoneController+Name.swift` on the phone or
`PodLoanWatchController+Name.swift` on the watch. Every row with an
acting device is one case of `LoanControl.decide` (`LoopCore/PodLoan/LoanControl.swift`), in this table's order, with
the row's reason as its comment, and one test in `LoopTests/LoanControlTests.swift`; a different ruling for a row is
a change to that case and that test.

Columns:
- **Control state:** pod held by · how it got the pod · loan (number, start) · took over on silence at · looper's
  latest tap.
- **Physical configuration:** phone where / alive · watch where / alive.
- **Change:** what changed in the world.
- **Phone sees:** believes · sensor · pod · heard from the watch. **Watch sees:** the same four.
- **Result:** query · answer · action · pod held by afterwards · time without looping · looper sees.
- **Status · Code · Why.**

| # | Pod held by | How it got the pod | Loan | Took over on silence at | Looper's latest tap | Phone | Watch | What changed | Phone believes | Phone: sensor | Phone: pod | Phone heard from the watch | Watch believes | Watch: sensor | Watch: pod | Watch heard from the phone | Query | Answer | Action | Held by afterwards | Time without looping | Looper sees | Status | Code | Why |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 Start, phone near | phone | resting state | none | none | Start on the watch, now | near, alive | on wrist, alive | Start tapped on the watch | it holds the pod | fresh | holding, reads | the Start request | the phone holds the pod | fresh | not touched | nothing yet | the request is the query (watch → phone) | a grant | phone releases the pod and holds its dosing; watch takes over (transfer G) | watch, by grant | seconds | watch: Sport Mode page; phone: banner "Sport Mode Active" | built | phone `+Grant`, watch `+Start` | The looper chose the watch and the phone is there to hand over: the ordinary case. |
| 2 Start, phone away or dead | phone | resting state | none | none | Start on the watch, now | away, or dead | on wrist, alive | Start tapped on the watch | it holds the pod (as of when it left), or dead | none, or dead | out of reach, or dead | nothing | the phone holds the pod | fresh | not touched | nothing | the request (queued) | silence after 10 s | prompt "Start without it?"; on the tap, the watch starts from its stored copy and checks the pod's total first | watch, started without the phone | 10 s plus the tap | watch: on screen, the offer | built | watch `+Start`, `+Seize` | The looper asked for Sport Mode and the phone cannot grant it. Starting from the stored copy is entering a mode, which needs the looper's tap (rule 6), so the system offers it as the alternative to the refused Start (rule 7). The query's silence decides when to offer, not the reachability flag, which says only whether the phone's app can take a live message this second. |
| 3 Phone dies, no loan | phone | resting state | none | none | any | dead | on wrist, alive | the phone dies | dead | dead | dead | dead | the phone holds the pod | fresh | not touched | nothing; the phone's loop goes stale | none | none | tell: nobody takes the pod; a pre-scheduled watch warning, pushed out by every word from the phone, fires after 25 min of silence, after the phone's own Loop Failure at 20 | nobody; the pod runs its schedule within 30 min | until the looper starts Sport Mode or charges the phone | watch · notification (time-sensitive) "Not Hearing From iPhone: your watch hasn't heard from your iPhone for 25 minutes, so it can't tell whether anything is looping. If the iPhone is off or not with you, open Loop on the watch to start Sport Mode." · on screen: the phone's loop ring (red after 16 min, as in Loop) and "Not hearing from iPhone" after 25 min | deliberate exception for control; the warning is built | `LoanControl` row 3; watch `NotHearingFromPhoneAlert` | Looping wins under rule 3, but taking the pod here would be entering Sport Mode without a tap, which rule 6 forbids, and the watch cannot tell a dead phone from one left at home. Following rule 3 would start Sport Mode every time the looper walked away from the phone. The cost is Loop's own: away from a working phone, nothing loops. Telling is what remains. The watch knows this state (no loan, no word from the phone), and it is easy to enter without choosing it (a forgotten phone), so it warns once. The phone talks with its loop cycles, so a phone that stops looping goes quiet too; its own pre-scheduled Loop Failure (20 min) reaches the watch when near, or through a cellular watch's relay, so the watch's comes after it, as the backup for a dead phone or a watch with no route to it. |
| 4 Phone back, no loan | phone | resting state | none | none | any | near again, alive | any | the phone comes back into reach | it holds the pod | fresh | reads it | nothing | the phone holds the pod, or dead | — | — | — | none | — | carry on; the reading's check finds nothing to explain | phone | none beyond the time away | nothing | built | phone `+Ledger` | The resting state, resumed. |
| 5 Insulin seen, no loan answers | phone | resting state | none, as far as the phone knows | none | any | near, alive | any | a reading shows the pod delivered more or less than the phone's records explain, beyond 0.20 U | it holds the pod | fresh | reading shows the difference | nothing | idle, or dead | — | — | the phone's query | phone → watch | silence, or "I hold nothing" | book (if more was delivered), keep looping, tell; record the time as "took over on silence" | phone | none | phone: notification "Insulin Estimated After Sport Mode: … booked as a bolus" (more delivered) or "Insulin On Board May Be Overstated" (less) | built | phone `+Ledger` `followAnotherControllersInsulin` | The phone already holds the pod, so silence keeps it there. A real loan answers (rows 17, 18); no answer means either a watch that started alone and died (row 18) or, without a loan, an uncertain-delivery bolus or a testing artifact. Booking covers all three conservatively. |
| 6 Message from a closed loan | phone | any | the phone has ended loan n | any | any | near, alive | near, alive | a message arrives from the watch about loan n | it holds the pod | fresh | holding | a report, records or an offer for loan n | it holds loan n | fresh | trying | nothing | none | — | send the stop for loan n again (at most every 20 s) | phone | none | watch: "Sport Mode ended. Your iPhone has the pod" | built | phone `+Mirror` `resendRevokeForClosedSession` | The watch missed the stop; it gets it again. |
| 7 End, phone near | watch | grant | n | none | End on the watch, now | near, alive | on wrist, alive | End tapped on the watch | the watch holds loan n | fresh | released | the hand-back offer | it holds loan n | fresh | holding | an acknowledgement | the offer is the query (watch → phone) | acknowledged | hand back (transfer H) | phone | seconds | watch: "returning records…", then the phone's page; phone: banner gone | built | watch `+Handback`, phone `+Records` | The looper's latest decision, and both devices are there to carry it out. |
| 8 End, phone away | watch | grant | n | none | End on the watch, now | away, or dead | on wrist, alive | End tapped on the watch | the watch holds loan n, or dead | none, or dead | out of reach | nothing | it holds loan n | fresh | holding | nothing | the offer (queued) | silence after 10 s | refuse the End; the loan continues | watch | none | watch: on screen, not a notification: "iPhone isn't nearby, so the pod can't be handed back. Sport Mode keeps looping. To stop automatic dosing, open the loop on the watch." | built | watch `+Handback` | This refuses the looper's express intent, and the reason has to be honest. End names an action, giving the pod to the phone, which cannot be done without the phone. What the looper meant is one of two things the watch cannot tell apart: end Sport Mode (impossible here) or stop dosing (possible, by opening the loop). So the refusal says both. How the watch knows the phone is away: it sends the offer and waits, like every other query. The reachability flag reports only whether the phone's app can take a live message this second, and would refuse with the phone in the next room. An offer that lands late only stores records; nothing changes hands. |
| 9 Take Back on the phone | watch | grant, or started alone and adopted | n | none | Take Back on the phone, now | near, alive | on wrist, alive or dead | Take Back tapped | the watch holds loan n | fresh | released | anything | it holds loan n, or dead | fresh, or dead | holding, or dead | the stop | none: a tap needs no query | — | take (reach the pod in 5 s, send the stop, check insulin; if the pod does not answer, refuse: transfer T) | phone | seconds | phone: banner gone; watch: "Sport Mode ended. Your iPhone has the pod" | built | phone `+Reclaim` | A tap is the looper's latest decision. |
| 10 Watch dies, phone near | watch | grant | n | none | Start on the watch, earlier | near, alive | on wrist, dead | the watch dies | the watch holds loan n | fresh | released | nothing for more than a cycle | dead | dead | dead | dead | phone → watch, once the report is overdue | silence after 30 s | take; record the time as "took over on silence" | phone | 6–11 min, then 30 s | phone: notification "Watch Not Responding: this phone is taking the pod back; insulin the watch gave is counted" | built | phone `+Hold` | A live watch on the wrist, with the body in reach, answers within seconds. Silence means it is not looping, and looping conservatively is safer than not looping. The watch's first word would end a mistake. When it comes back: row 12. |
| 11 Watch dies, phone away | watch | grant | n | none | Start on the watch, earlier | away, or dead | on wrist, dead | the watch dies | the watch holds loan n, or dead | none | out of reach | nothing | dead | dead | dead | dead | none: no device can see the body | — | nothing | nobody; the pod runs its schedule within 30 min | until a device is back (rows 12, 13, 18) | nothing | accepted | — | Nobody can act. Loop with a dead phone is the same. |
| 12 Watch back, phone holds the pod | phone | took back by tap, or took over on silence | n (closed) | none, or when the phone took over | Start on the watch, earlier; or Take Back | near, alive | on wrist, back from dead | the watch comes back | it holds the pod | fresh | holding | "I hold loan n" (the watch's query) | it holds loan n, as of when it died | fresh | not touched | nothing at launch | watch → phone, once its link has started; live when the phone is reachable, and queued | the stop for loan n | stand aside, before any dose | phone | none | watch: "Checking with your iPhone…" while it asks, then "Sport Mode ended. Your iPhone has the pod" | built | watch `+Resume`, phone `+Mirror` | The watch was out of the conversation (rule 5); the phone holds the pod; the watch stays out and the looper starts again if wanted. The question waits for the watch's link to the phone to start: a message sent before that is lost. It goes by the live path when the phone is reachable, and queued as well; queued alone, the answer can take longer than the wait, and the watch would loop beside the phone until it arrived. The watch shows that it is checking, and builds nothing that can reach the pod until the check ends. |
| 13 Watch back, nobody else holds the pod | watch | grant, or started alone | n | none | Start on the watch, earlier | away or dead; or near and still lending | on wrist, back from dead | the watch comes back | the watch holds loan n, or dead | — | released, or out of reach | "I hold loan n", or nothing | it holds loan n | fresh | not touched | nothing | watch → phone | silence (phone away), or nothing back (phone still lending) | carry on: the loop gets the pod; its first reading closes the window from the last reading before it died, booking what its records cannot explain | watch | 30 s plus the first reading | watch: "Checking with your iPhone…" for up to 30 s, then a note if anything was booked: "0.55 U the watch had no record of, counted as insulin on board" | built | watch `+Resume`, `+Seize` | The only device there carries on with what it was last told (rule 5). More than 6 hours off: no resume, records go home, "Sport Mode Ended" (rule 1). |
| 14 Watch on a far charger, phone near | watch | grant | n | none | Start on the watch, earlier | near, alive | off wrist out of reach, alive | the watch goes on a charger out of the pod's reach | the watch holds loan n | fresh | released | nothing for more than a cycle (a cycle that cannot reach the pod sends no report) | it holds loan n | none | unreachable | the phone's query | phone → watch | "I hold loan n but cannot reach the pod" | take, as on silence; record the time | phone | 6–11 min, then 30 s | phone: notification "Watch Not Responding: this phone is taking the pod back…"; watch: on screen "Sport Mode ended. Your iPhone has the pod" | built | phone `+Hold`, watch `+Handback` (the answer) | Rule 2 protects a device that is looping. This one holds the loan and cannot act on it. It is alive and answers, so silence cannot be the signal; the answer carries the fact, and "cannot reach" is acted on like silence. The watch could give up the pod by itself after a failed cycle, but it cannot tell whether the phone is there to take it, and giving up with nobody there gains nothing. The phone knows it is near and can loop, so the phone decides. Rare: a charger by the bed is within reach. |
| 15 Watch out of reach, phone away | watch | grant | n | none | Start on the watch, earlier | away, or dead | off wrist out of reach, alive | both away from the body | the watch holds loan n, or dead | none | out of reach | nothing | it holds loan n | none | unreachable | nothing | none | — | nothing; the watch's own "not looping" warnings | nobody | until a device is back | watch: notifications "Loop hasn't completed" at 20 and 40 min, 1 and 2 h, on a watch nobody is wearing | accepted | watch `LoopStallWatchdog` | Nobody can act; the warnings land on the watch, which is not worn. |
| 16 Phone moves during a loan | watch | grant | n | none | Start on the watch, earlier | leaves, dies, or comes back | on wrist, alive | the phone changes place or state | the watch holds loan n | any | released | reports each cycle | it holds loan n | fresh | holding | anything | none | — | carry on | watch | none | phone: banner "Sport Mode Active" when looked at | built | — | The latest decision stands; nothing about the phone changes it. |
| 17 Phone returns, watch started alone and alive | watch | started without the phone | n, started at T | none | Start Anyway on the watch, earlier | near again, alive | on wrist, alive | the phone comes back | it holds the pod (it was never told) | fresh | reads it: insulin it cannot explain | "I hold loan n" (on reach), or nothing yet | it holds loan n | fresh | holding | anything | phone → watch, on seeing the insulin; or none, if the watch's word came first | "I hold loan n" | stand aside, adopt the loan; from here rows 7–16 apply | watch | none | phone: banner "Sport Mode Active" (no prompt, no notification) | built | phone `+Mirror`, `+Ledger` | The latest decision was the looper's Start on the watch, made without the phone; the phone's return is not a decision, so it raises no prompt. |
| 18 Phone returns, watch started alone and dead | watch (dead) | started without the phone | n, started at T | none | Start Anyway on the watch, earlier | near again, alive | on wrist, dead | the phone comes back | it holds the pod | fresh | insulin it cannot explain | nothing | dead | dead | dead | dead | phone → watch | silence | book what it cannot explain, keep looping, tell; record the time as "took over on silence" | phone | none (the phone was already looping when it read) | phone: notification "Insulin Estimated After Sport Mode: Sport Mode probably started away from the phone: … booked as a bolus" | built | phone `+Ledger` | The watch is out of the conversation; the phone holds the pod and keeps it. When the watch comes back: row 19. |
| 19 Watch back after the phone took over | phone | took over on silence (row 18, or row 10/14) | n, started at T1 | T2, after T1 | Start Anyway on the watch, at T1 | near, alive | on wrist, back from dead | the watch comes back | it holds the pod | fresh | holding | "I hold loan n, started at T1" | it holds loan n, as of when it died | fresh | not touched | nothing at launch | watch → phone | the stop for loan n | stand aside, before any dose | phone | none | watch: "Checking with your iPhone…" while it asks, then "Sport Mode ended. Your iPhone has the pod" | built | phone `+Mirror` (`refusesRevivedLoan`) | Two rules meet. A watch's word normally makes the phone stand aside (rule 2), because a watch that says it holds a loan is usually looping it. But this watch was out of the conversation: the phone queried, got nothing, and has looped since. Its claim is about the time before it died. Standing aside would move control, silently, to a device the looper stopped using, reversing the takeover without a tap (rule 5). The phone tells the cases apart by one fact it holds, when it took over: a loan started before that is a revived claim, refused; one started after is a fresh Start the looper made while the phone was away, honoured (row 17). Accepted cost: if the watch was merely slow to answer, the takeover was a mistake and this keeps it; one tap restores the loan, and the watch says what happened. |
| 20 Phone returns, watch started alone on a far charger | watch | started without the phone | n | none | Start Anyway on the watch, earlier | near again, alive | off wrist out of reach, alive | the phone comes back | it holds the pod | fresh | insulin it cannot explain | nothing | it holds loan n | none | unreachable | the phone's query | phone → watch | "I hold loan n but cannot reach the pod" | as on silence: book, keep looping, tell; record the time | phone | none | as row 18 | built | phone `+Ledger`, `+Hold` | As row 14: a holder that cannot reach the pod is treated as absent. When the watch is back in reach it queries and gets the stop (row 19). |
| 21 End, phone away, watch started alone | watch | started without the phone | n | none | End on the watch, now | away, or dead | on wrist, alive | End tapped | the phone holds the pod (never told), or dead | — | out of reach | nothing | it holds loan n | fresh | holding | nothing | the offer (queued) | silence after 10 s | refuse, as row 8 | watch | none | as row 8 | built | watch `+Handback` | As row 8. |
| 22 Watch started alone dies, phone away | watch (dead) | started without the phone | n | none | Start Anyway on the watch, earlier | away, or dead | on wrist, dead | the watch dies | the phone holds the pod (never told), or dead | none | out of reach | nothing | dead | dead | dead | dead | none | — | nothing | nobody | until rows 13 or 18 | nothing | accepted | — | Nobody can act. |
| 23 Both dead | whoever held it | any | any | any | any | dead | dead | both die | dead | dead | dead | dead | dead | dead | dead | dead | none | — | nothing; the pod runs its schedule | nobody | until a device is back | nothing | accepted | — | Nothing to decide. |

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
looper tries again after it. A take-over on silence, where nobody can retry, waits for the pod to finish the bolus
it reports. The pod has one connection, so the device reading it cannot be raced by a new bolus. An offline Start
cannot ask the phone and takes the pod whatever it is giving: the phone's records are trued up from the pod's
delivered total when it is back with the pod.

| Transfer | Step that fails | Who notices | What it sees | What it does | Pod held by | Looper sees | Status |
|---|---|---|---|---|---|---|---|
| **G** grant (phone → watch) | the request is lost | watch | silence 10 s after the request | prompt "Start without it?" if it has a stored copy, else "No response from iPhone" | phone | watch: on screen | built |
| G | the grant is lost or the takeover stalls | phone | no confirmation 20 s after the grant | query the watch | nobody (the phone has released; the watch has not taken) | — | built |
| G | ″ | phone | answer "I know no such grant" | take back at once | phone | phone: notification "The watch didn't take the pod. This phone kept it." | built |
| G | ″ | phone | silence 30 s after that query | take back | phone | ″ | built |
| G | ″ | phone | answer "taking over" | wait until the grant's lease ends (60 s), then query once more and take back on silence | the watch if it lands | ″ if it does not | built |
| G | the phone's own bolus is still being given at the Start | phone | its pump's bolus state | deny the Start: "A bolus is still being given. Try again in N seconds." | phone | watch: on screen, the reason, with a haptic | built |
| G | the takeover fails on the watch | watch, then phone | the watch reports failure | the phone takes back at once | phone | watch: on screen, the reason | built |
| G | the looper cancels at the offline offer, and the grant arrives after that | watch | a grant for a Start no longer wanted | answer "takeover failed": Sport Mode is entered only by a tap, and the cancel withdrew it; a new Start asks afresh | phone | phone: takes the pod back at once, as above | built |
| G | the grant is numbered at or below a loan the watch already knows | watch | a stale grant | answer "takeover failed" | phone | — | built |
| G | the confirmation is lost | phone | the query is answered "I hold loan n" | treat the takeover as complete | watch | — | built |
| **S** offline start | the pod does not answer within the lease | watch | no pod reading | back to rest | phone (as before) | watch: "Sport Mode start expired before the pod answered" | built |
| **H** hand-back (watch → phone) | the watch's bolus is still being given at End | watch | its pump's bolus state | refuse the End: "A bolus is still being given. Try again in N seconds."; the loan continues | watch | watch: on screen over the bolus progress, with a haptic | built |
| H | the phone is away at End | watch | silence 10 s after the offer | refuse (row 8) | watch | row 8 | built |
| H | the phone acknowledged the first offer, later offers go unanswered | watch | no acknowledgement; resends every 15 s | keep resending, by every path, for the 2-min budget | watch, still looping | watch: "ending…" | built |
| H | the final offer (sent after dosing stopped) is not acknowledged within the budget | watch | no acknowledgement | let the pod go and keep sending records; the phone takes the pod when they land, or when its overdue query is answered "I hold nothing" (counted as silence) | nobody until the phone takes it (seconds, or 6–11 min if every message was lost) | watch: notification "End Not Confirmed: the watch has stopped dosing… open Loop on the iPhone and tap the pod tile" | built. The transfer rule's second half: the watch cannot tell whether its final offer arrived, and resuming would dose beside a phone that may already be taking the pod, so the resting state it is |
| **T** take-back (phone ← watch's pod) | the pod does not answer within 5 s | phone | no link | refuse; the loan is unchanged | watch | phone: "Couldn't Reach the Pod" | built |
| T | the pod is giving the watch's bolus when the phone reaches it | phone | the pod's status, read before the stop | a tapped take-back is refused: "A bolus is still being given. Try again in N seconds."; a take-over on silence waits for the pod to finish, its link limit starting again after | watch, until the bolus ends | phone: notification "Wait for the Bolus" (tap); nothing (silence) | built |
| T | the stop is lost (watch off) | watch, at return | its query is answered with a stop | stand aside (row 12) | phone | row 12 | built |
| T | the pod is not reached within 12 s of a take-back | phone | link still down | escalate: search for the pod by its advertisement. The search ends with the take-back, reached or at its 5-min limit, and connects go back to the phone's own handle | phone | — | built |
| T | the pod cannot be read after the take-back | phone | the insulin check is owed | hold dosing until the pod answers, then check | phone, not dosing | — | built |

---

## 7. Testing artifacts

Failures only a test can produce. They are logged when recognised; no warning is built for them.

- **Pod emulator on a counter, devices carried away.** The watch gets no sensor or pod wakes, watchOS stops its app,
  it goes silent, and a phone back near the counter takes the pod (row 10 by mistake).
- **Pod emulator not delivering or not reachable.** The pod's total does not move while the records expect basal, so
  the hand-back check reports insulin overstated, and the phone's reconnect may need its escalation.
- **Pod emulator needs a reboot** after some failed takeovers.
- **Water pod** off the body: as the emulator on a counter.
- **Sensor emulator out of reach** while the pod is reachable: the watch's cycles refuse for lack of glucose; the
  phone's "near the body" test fails, so it never queries.

---

## 8. Known limits and open questions

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
