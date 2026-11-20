# Mobile CI lessons

Every iPad or iPhone CI or build failure goes here, with its cause and fix, so it doesn't happen twice. Mac jobs are scarce (README, "Building"): read this before pushing mobile work. Newest first.

## Time limits

- **Nov 19: "The job was not acquired by Runner of type hosted even after multiple attempts"** (ui-check on 0f84b86). GitHub had no Mac free for 15 minutes and failed the run before a single step; nothing in the repo caused it. Fix: re-run the run (Actions › the run › Re-run), don't push to retrigger. Whoever pushed should check the run is actually running, not just queued: this one sat failed overnight because the failure looked like any other.
- **Nov 19: ui-check's iPad step hit its 70-minute limit, the iPhone step its 40.** Every test that ran passed; the runner was slow (the same tests took up to twice as long as on Nov 18), so `TutorPanelTests.testTutorChatDark` and `TimeTrackingPhoneTests` were cut off. Fix: iPad step 95, iPhone step 55, job 170. When the suite grows, raise these with it: a limit is for a hung run, not for a slow Mac.
- **Nov 18: the iPhone step hit 25 minutes** on main (12 tests, about 26 minutes). Raised to 40, job 130 (PR #42).
- **Nov 18: `ApplicationsPhoneTests` failed with a simulator launch timeout**, not an assertion. A re-run passed it. Read the failure line before changing code: "Failed to launch" or "timed out waiting for the app to idle" is the runner, not the app.

## Writing UI tests

- **SwiftUI lists and forms only create the rows on screen.** A row below (or above) the fold doesn't exist for XCTest: scroll until it appears, both ways, with a bounded loop (`while !row.waitForExistence(timeout: 3) && n < 6 { app.swipeUp() }`). Nov 18-19: Study's R1 row, Upload's "File it", the workstream page's Spanish link after setting Spanish up.
- **Wait for content, not a fixed sleep.** A web tool page (VSEPR) screenshotted after `sleep(5)` came out blank; wait for `app.webViews.firstMatch.staticTexts.firstMatch`.
- **An `accessibilityIdentifier` on a VStack hides its children's ids**: add `.accessibilityElement(children: .contain)`.
- **Nov 20 (new look, PR #45): an `accessibilityIdentifier` on an HStack row goes to every child, buttons included.** The subject row's id landed on its arrow, so `el("subject-…").tap()` opened the folder instead of stepping inside, and the name's static text lost its label match (`staticTexts["Physics HL"]` failed in SpanishPadTests). Fix: no id on a row that holds a button and a name; tests tap the name's text.
- **Nov 20: a view that fills a whole fan (or any big container) is found at its frame's centre.** The quick ring's choices were full-fan views with an overridden `accessibilityFrame`; XCTest tapped the fan's middle (the ring's own button) and nothing was picked. Fix: the small chip is the accessibility element.
- **Nov 20: a wider font (Onest) pushed buttons below a scroll view's fold.** The Spanish memory review's Save sat at the bottom of a 420 pt scroll area; on the iPhone it ended under the tab bar and the tap missed. Fix: the review's buttons sit under the scrolling part. After a font or spacing change, expect tests that tap near the bottom of a sheet to need a look.
- **Nov 20: a row that fills up with more controls stops being hittable at its end.** The bar's Draw row took the tools, ten colours and six sizes plus the pills; Extra bold went off screen and PenOptionsTests' width checks failed. Fix: Insert space and + moved to Insert, page and zoom to the top row.
- **Nov 20: a query over every button with a label can time out ("Timed out while evaluating UI query").** NewLookTests' `button("Pen")` (all matches, then `isHittable` on each) timed out right after the quick ring's double tap, while the board was busy redrawing. Fix: the bar's tool buttons have ids (`board-tool-<tool>`), and the test asks `app.buttons["board-tool-pen"].firstMatch` with a wait. Prefer an id query to a label scan wherever a screen has many buttons.
- **Tests share the simulator's UserDefaults.** A test that opens something remembered (a subject's folder) changes the next test's sidebar; the test hooks reset it (`-NexusTestNestedNotebooks` clears `openNotebooks` and `openSubjects`).
- **When a screen's way in changes, change every test that goes there.** Nov 19: the sidebar lost its Study tools and Spanish rows, so the Spanish tests open Spanish from the class's Study page (`study-spanish`).

## Workflows

- **One Mac job per check.** `phone-check.yml` (a separate iPhone + iPad matrix) came back to main with the Applications PR; its jobs queue beside ui-check's and were cancelled on Nov 19 after waiting for a runner. ui-check already runs both devices.
