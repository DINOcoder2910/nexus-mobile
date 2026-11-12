# Nexus mobile

The iPad and iPhone side of [Nexus](https://github.com/DINOcoder2910), a personal, file-based workspace. Only the app's code lives here; notes never do.

## What it does now

One app for the iPad and the iPhone. On the iPhone the sidebar is the first screen of a stack (it opens on Today, with the sidebar one step back), the Planner's days are stacked instead of side by side, and a board draws with the finger (there is no Pencil).

- **The planner side of Nexus**, on the same data folder as the laptop: a sidebar with Today, Planner, Calendar, Tasks, the workstreams by group, Inbox and Someday.
  - **Today**: the plan (times first), repeats that fall today, deadlines that need you, what slipped (with Today and Move all to today), tomorrow, and the key dates ahead.
  - **Planner**: 3 days or a week, slipped tasks on top, the task bank below; drag a task onto a day.
  - **Calendar**: the device's own calendars through EventKit (whatever accounts are added in iOS Settings: Google, the school's Microsoft 365, iCloud, subscribed ICS links) with the tasks planned at a time and the deadlines. Day, 3 days, Week (iPad), Month and List; tap an event for the system's event sheet (edit, delete), double-tap an empty time for a new event, drag a task's block to plan it at another time. Today and the Planner show the day's events too. Nothing of it goes into the data folder (the laptop keeps its calendar sync in its own profile too, `docs/areas.md` "Calendar").
  - **Tasks**: the laptop's lenses (All, Deadlines, Waiting on, No date, Slipped, Done, Someday) and search.
  - **A workstream's page**: its task tree, Someday and Done, its notes.md and its files.
  - **The task panel**: title, ★, deadline, planned days and times, estimate, subtasks, Someday; waiting, repeats, tags and the note are shown.
  - **Add a task** anywhere with +, into a workstream or the Inbox.
- **Notebooks**, as on the laptop: `notebooks/<notebook>/<section>/<board>.board` in the data folder, made, renamed and opened from the sidebar.
  - **A board**: PencilKit ink on an endless canvas that grows in every direction, over PDF printouts (pages drawn only near the view, Contents with the PDF's chapters and go to page), images, shapes (rectangle, ellipse, line, arrow) and typed text blocks (markdown, size, colour, background, tick a checkbox with a tap).
  - **Tools** (the grid button): the Study tools (Molecules, VSEPR chart, Enthalpies, from the laptop's `.nexus-tools/`) and any .html file in the notebook, used in a panel from the right; put one on the board as a live card (tap it twice to use it again, where you left it) or as a picture. Tools run offline with no access to your files.
  - Fingers pick, move and resize items; hold the Pencil still at the end of a stroke to snap it to a line, circle, ellipse or polygon.
  - Saved in the laptop's board format, byte for byte, 600 ms after an edit: only the tiles that changed are written, and every stroke keeps its id, so a sync merge sees only what changed. Another device's write is read in when nothing here is unsaved.
  - **Search boards**: handwriting read on the iPad with Vision, plus typed text; tap a hit to open the board there. The index lives in the app, never in the data folder.
  - The ink test's own boards were copied once into **Notebooks › Ink test**; the originals stay under Ink test boards.

- **Shortcuts**, editable in **Settings › Shortcuts**, with a **Laptop | iPad** switch: search, collapsible sections, conflicts in red (a board key that takes over an app-wide one is a grey note), Conflicts only, a reset beside each changed key and Reset all.
  - **iPad keys** (with a hardware keyboard; hold ⌘ to see them): ⌘1–6 Today, Planner, Tasks, Notebooks, Inbox, Someday; ⌘, Settings; ⌘N new task; ⌘F search tasks; ⇧⌘N new notebook; ⌘Z undo the last change; on a board ⌘W close, ⌘Z / ⇧⌘Z undo and redo, ⌘= ⌘- ⌘0 zoom, ⌘G PDF contents, P E L pen, eraser, lasso, T text, ↩ edit, ⌫ delete. Tap a key to change it and press the new one, or pick it without a keyboard; a key another shortcut has there offers Swap or Replace.
  - **Gestures** on a board: two-finger tap undo, three-finger tap redo, the Pencil's double-tap and squeeze doing what Settings › Apple Pencil says, each movable to another action or off.
  - Kept in the data folder as `shortcuts/ipad.yaml` (the iPad writes it whole; the laptop may change a `keys:` line). The Laptop side reads `shortcuts/laptop.yaml` and edits just the changed `keys:` line. The format is `docs/data-format.md` "Shortcuts" in the Nexus repo.

## The data folder

The app reads `On My iPad › Nexus › nexus-data` (or a folder picked from Files) in the laptop's format (`docs/data-format.md` in the Nexus repo). Reading never writes. Every change is a line-level edit of one `tasks.yaml` or `inbox.yaml`, checked by parsing the result before it is saved, so comments, order and formatting stay and the laptop sees a one-line change. A file that doesn't parse, a task without an id, and a folder in another format version are read-only. The app looks for changes every few seconds and when it comes back to the front, so sync can write underneath it.

The pure part is the `NexusCore` package (`Packages/NexusCore`): the folder, the YAML edits, the planning model, the board files, shape snapping and capture parsing, with tests on a copy of the laptop's `dev/fixtures/data-vault` and the laptop's own board and shape tests.

## Sync

The iPad keeps its own full copy of the data folder and syncs it with the laptop through the hub on the always-on G14 PC (the protocol is `docs/sync.md` in the Nexus repo). It works offline; while the app is open a change shows on the other device within a few seconds.

To set it up on the iPad:

1. Start the hub on the G14 and sync the laptop with it first (the iPad never fills an empty hub).
2. Install Tailscale on the iPad and sign in with the same account as the G14, or be on the home Wi-Fi.
3. In Nexus, open **Settings › Sync** and fill in the **hub address** (the G14's Tailscale address or name, e.g. `http://100.x.y.z:8743`; without a port, 8743 is used), the **hub token** (the hub prints it on its first start), and **this device's name** (`iPad` unless you have more than one).
4. Turn on **Sync with the hub**. If the iPad's folder is empty, everything is downloaded. If it already has files that differ from the hub's, Nexus asks how to start: **Use the hub's copy** (recommended: the iPad's folder is moved aside to `nexus-data before sync <date>` in On My iPad › Nexus, then everything is downloaded) or **Merge with this iPad's files** (where a file differs, the iPad's version is kept beside it as a conflict copy).

Settings › Sync shows where things stand (Up to date, Syncing, Offline), lists conflict copies (files with `(conflict …)` in their name: open both, keep what you want, delete the copy) and files that are left alone because their name can't be used on Windows. If more than 25 files and more than a quarter of the folder disappear at once, sync stops and asks before deleting them on the hub. A folder without `nexus.yaml` is never synced, so a missing folder can't look like everything was deleted.

The code: `Packages/NexusCore/Sources/NexusCore/Sync*.swift` (the paths, the state, the hub's HTTP protocol and the client's cycle, tested against an in-process hub) and `Sources/Sync/` (running it while the app is open, the token in the Keychain). The sync state lives in Application Support, never in the data folder.

## Building

There is no Mac in the loop: every push builds on a GitHub-hosted Mac (`.github/workflows/build.yml`), running the NexusCore tests and building the app side by side. The project file is generated from `project.yml` with XcodeGen, and the build is unsigned. `main` publishes **Releases › latest › NexusMobile.ipa**; any other branch publishes **Releases › preview**.

## Installing

Install `NexusMobile.ipa` on the iPad with [Sideloadly](https://sideloadly.io) on Windows, signed with a free Apple ID (a spare one is best). Free signing lasts 7 days; Sideloadly renews it automatically when the iPad is awake on the same Wi-Fi as the PC running it. Installing a new build over the old one keeps the app's files.
