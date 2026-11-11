# Nexus mobile

The iPad (and later iPhone) side of [Nexus](https://github.com/DINOcoder2910), a personal, file-based workspace. Only the app's code lives here; notes never do.

## What it does now

- **The planner side of Nexus**, on the same data folder as the laptop: a sidebar with Today, Planner, Tasks, the workstreams by group, Inbox and Someday.
  - **Today**: the plan (times first), repeats that fall today, deadlines that need you, what slipped (with Today and Move all to today), tomorrow, and the key dates ahead.
  - **Planner**: 3 days or a week, slipped tasks on top, the task bank below; drag a task onto a day.
  - **Tasks**: the laptop's lenses (All, Deadlines, Waiting on, No date, Slipped, Done, Someday) and search.
  - **A workstream's page**: its task tree, Someday and Done, its notes.md and its files.
  - **The task panel**: title, ★, deadline, planned days and times, estimate, subtasks, Someday; waiting, repeats, tags and the note are shown.
  - **Add a task** anywhere with +, into a workstream or the Inbox.
- **Boards** from the ink test (PencilKit, PDFs with chapters and go to page), kept in the sidebar until notebooks replace them.

## The data folder

The app reads `On My iPad › Nexus › nexus-data` (or a folder picked from Files) in the laptop's format (`docs/data-format.md` in the Nexus repo). Reading never writes. Every change is a line-level edit of one `tasks.yaml` or `inbox.yaml`, checked by parsing the result before it is saved, so comments, order and formatting stay and the laptop sees a one-line change. A file that doesn't parse, a task without an id, and a folder in another format version are read-only. The app looks for changes every few seconds and when it comes back to the front, so sync can write underneath it.

The pure part is the `NexusCore` package (`Packages/NexusCore`): the folder, the YAML edits and the planning model, with tests on a copy of the laptop's `dev/fixtures/data-vault`.

## Building

There is no Mac in the loop: every push builds on a GitHub-hosted Mac (`.github/workflows/build.yml`), running the NexusCore tests and building the app side by side. The project file is generated from `project.yml` with XcodeGen, and the build is unsigned. `main` publishes **Releases › latest › NexusMobile.ipa**; any other branch publishes **Releases › preview**.

## Installing

Install `NexusMobile.ipa` on the iPad with [Sideloadly](https://sideloadly.io) on Windows, signed with a free Apple ID (a spare one is best). Free signing lasts 7 days; Sideloadly renews it automatically when the iPad is awake on the same Wi-Fi as the PC running it. Installing a new build over the old one keeps the app's files.
