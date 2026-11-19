# Mobile CI lessons

Every iPad or iPhone CI or build failure goes here, with its cause and fix, so it doesn't happen twice. Mac jobs are scarce (README, "Building"): read this before pushing mobile work. Newest first.

## Time limits

- **Nov 19: ui-check's iPad step hit its 70-minute limit, the iPhone step its 40.** Every test that ran passed; the runner was slow (the same tests took up to twice as long as on Nov 18), so `TutorPanelTests.testTutorChatDark` and `TimeTrackingPhoneTests` were cut off. Fix: iPad step 95, iPhone step 55, job 170. When the suite grows, raise these with it: a limit is for a hung run, not for a slow Mac.
- **Nov 18: the iPhone step hit 25 minutes** on main (12 tests, about 26 minutes). Raised to 40, job 130 (PR #42).
- **Nov 18: `ApplicationsPhoneTests` failed with a simulator launch timeout**, not an assertion. A re-run passed it. Read the failure line before changing code: "Failed to launch" or "timed out waiting for the app to idle" is the runner, not the app.

## Writing UI tests

- **SwiftUI lists and forms only create the rows on screen.** A row below (or above) the fold doesn't exist for XCTest: scroll until it appears, both ways, with a bounded loop (`while !row.waitForExistence(timeout: 3) && n < 6 { app.swipeUp() }`). Nov 18-19: Study's R1 row, Upload's "File it", the workstream page's Spanish link after setting Spanish up.
- **Wait for content, not a fixed sleep.** A web tool page (VSEPR) screenshotted after `sleep(5)` came out blank; wait for `app.webViews.firstMatch.staticTexts.firstMatch`.
- **An `accessibilityIdentifier` on a VStack hides its children's ids**: add `.accessibilityElement(children: .contain)`.
- **When a screen's way in changes, change every test that goes there.** Nov 19: the sidebar lost its Study tools and Spanish rows, so the Spanish tests open Spanish from the class's Study page (`study-spanish`).

## Workflows

- **One Mac job per check.** `phone-check.yml` (a separate iPhone + iPad matrix) came back to main with the Applications PR; its jobs queue beside ui-check's and were cancelled on Nov 19 after waiting for a runner. ui-check already runs both devices.
