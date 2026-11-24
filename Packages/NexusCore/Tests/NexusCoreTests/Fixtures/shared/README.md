# Shared cases

Folders and files with the answers both apps must give, for the rules the laptop and the iPad / iPhone each implement. The laptop runs
them in `dev/unit-shared.mjs` (with every unit run); the iPad's CI runs the same files in nexus-mobile's
`Packages/NexusCore/Tests/NexusCoreTests/SharedCasesTests.swift` (`swift test`, on every push). So a rule can't change on one side
without failing on the other, and when the Rust core takes a rule over (the switch-over plan, step 3 on), it passes the same cases first.

## The rules

- `order/<case>/`: one task order for a day (`renderer/src/dayorder.js`, NexusCore `DayOrder.swift`): tasks with a time by time (before
  the day-start hour is that night's, so last), then your own order for the day (`nexus-day-order.yaml`), then deadline (none last), then
  file order (the task file's path, then the task's place in it). Never by name. `data/` is a whole data folder; `case.json` has `today`,
  `dayStart` and `expect`: `today` (Today's plan: planned today, plus due today and not planned) and `days` (each day's planned tasks,
  as the Planner's days, the Calendar and the iPad's Today list them).
- `day-order-file/cases.json`: reading and writing `nexus-day-order.yaml` (`read`, `write`, `set`) and reading a time for the order (`time`).
- `recordings/cases.json`: the recording format (`docs/data-format.md` "Recordings"): a time as a clock, a start time as the summary
  says it, the status from the files, Claude's answer read into a proposal, `summary.md`, a filed task's note, `teaching.md`. The old app
  has no recordings, so the Rust core (`core/tests/shared.rs`) and NexusCore run it; `dev/unit-shared.mjs` only knows the folder.

- `capture/cases.json`: the capture line read into a task (`renderer/src/taskparse.js`, the core's `capture.rs`, NexusCore
  `CaptureParse.swift`), as `{title, ...facts, subs, flags}`; the answers are the laptop's table in `dev/unit-taskparse.mjs`.
- `fsrs/cases.json`: a study card after a grade (`renderer/src/studyfsrs.js`, the core's `study/fsrs.rs`, NexusCore `StudyFSRS.swift`),
  in UTC with the day starting at 4; worked from the FSRS-5 formulas.
- `tutor/cases.json`: the tutor's reply read as it streams in, one drawing step checked (`renderer/src/tutor/reply.js` and `steps.js`, the
  core's `tutor/`, NexusCore `TutorReply.swift` and `TutorSteps.swift`), and Check my maths (only the core's `tutor/maths.rs`: the laptop's
  new app and the iPad call it, so `dev/unit-shared.mjs` only reads those cases).

nexus-mobile's runner also sends every case through the Rust core as the iPad builds it (`core/ffi`, UniFFI), so the iPad's copy of the
core passes the same answers as its own Swift.

## Adding a case or a rule

- A case: a new folder (or a new entry in a `cases.json`) with the answer worked out by hand from the rule as `docs/data-format.md`
  states it, not printed from either app. Run `node dev/unit-shared.mjs`.
- A rule: a new folder here, a runner in `dev/unit-shared.mjs` and one in `SharedCasesTests.swift` (both list the rules they know, so a
  folder neither runs fails).
- Then copy the folder to nexus-mobile: `sh tools/shared-cases/copy.sh <this nexus checkout>` there (it replaces
  `Tests/NexusCoreTests/Fixtures/shared/` with this folder), and push both branches together.
