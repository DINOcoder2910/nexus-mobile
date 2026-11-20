# Mobile CI lessons

Every iPad or iPhone CI or build failure goes here, with its cause and fix, so it doesn't happen twice. Mac jobs are scarce (README, "Building"): read this before pushing mobile work. Newest first.

## Time limits

- **Nov 19: "The job was not acquired by Runner of type hosted even after multiple attempts"** (ui-check on 0f84b86). GitHub had no Mac free for 15 minutes and failed the run before a single step; nothing in the repo caused it. Fix: re-run the run (Actions › the run › Re-run), don't push to retrigger. Whoever pushed should check the run is actually running, not just queued: this one sat failed overnight because the failure looked like any other.
- **Nov 19: ui-check's iPad step hit its 70-minute limit, the iPhone step its 40.** Every test that ran passed; the runner was slow (the same tests took up to twice as long as on Nov 18), so `TutorPanelTests.testTutorChatDark` and `TimeTrackingPhoneTests` were cut off. Fix: iPad step 95, iPhone step 55, job 170. When the suite grows, raise these with it: a limit is for a hung run, not for a slow Mac.
- **Nov 18: the iPhone step hit 25 minutes** on main (12 tests, about 26 minutes). Raised to 40, job 130 (PR #42).
- **Nov 20: ui-check's iPad step hit its 95-minute limit** (PR #44, 06ee70c). Every test that ran passed, but `RichTextTests` took 1064 s and 1152 s, against 139 s and 144 s on the same code an hour earlier (the step from "reopened on the board" to "whole block closed" alone took 310 s in both themes), so the tutor tests were cut off. The iPhone step passed. Fix: re-run the failed job (Actions › the run › Re-run failed jobs), no push. If `RichTextTests` is that slow twice in a row, look at that test's waits, not the limit.
- **Nov 20: `SidebarTreeTests.testNestedNotebooksLight` failed on "Week 1's boards still show when it is closed"** (PR #44, which doesn't touch the sidebar tree). The same test in dark passed two minutes earlier in 117 s; the light run took 325 s, opening "School" took 29 s instead of 3, and the 5-second wait for the closed level ran out on a stalled simulator. Fix: that wait is 20 s. A test that passes in one theme and times out in the other in the same run is the runner: lengthen the wait for content, never drop the check.
- **Nov 18: `ApplicationsPhoneTests` failed with a simulator launch timeout**, not an assertion. A re-run passed it. Read the failure line before changing code: "Failed to launch" or "timed out waiting for the app to idle" is the runner, not the app.

## Writing UI tests

- **SwiftUI lists and forms only create the rows on screen.** A row below (or above) the fold doesn't exist for XCTest: scroll until it appears, both ways, with a bounded loop (`while !row.waitForExistence(timeout: 3) && n < 6 { app.swipeUp() }`). Nov 18-19: Study's R1 row, Upload's "File it", the workstream page's Spanish link after setting Spanish up.
- **Wait for content, not a fixed sleep.** A web tool page (VSEPR) screenshotted after `sleep(5)` came out blank; wait for `app.webViews.firstMatch.staticTexts.firstMatch`.
- **An `accessibilityIdentifier` on a VStack hides its children's ids**: add `.accessibilityElement(children: .contain)`.
- **When a screen's way in changes, change every test that goes there.** Nov 19: the sidebar lost its Study tools and Spanish rows, so the Spanish tests open Spanish from the class's Study page (`study-spanish`).

## Workflows

- **One Mac job per check.** `phone-check.yml` (a separate iPhone + iPad matrix) came back to main with the Applications PR; its jobs queue beside ui-check's and were cancelled on Nov 19 after waiting for a runner. ui-check already runs both devices.
