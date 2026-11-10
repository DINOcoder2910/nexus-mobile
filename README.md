# Nexus mobile

The iPad (and later iPhone) side of [Nexus](https://github.com/DINOcoder2910), a personal, file-based workspace. Only the app's code lives here; notes never do.

**Right now this is the ink test**: a small iPad app to judge whether Apple's pen engine (PencilKit) on a Nexus board feels as good as OneNote, and whether long PDFs stay smooth.

- A blank board that grows as you write.
- A board from a PDF: pages laid out down the board, room to write beside them, only nearby pages drawn so long PDFs stay light, a chapter list from the PDF's own outline, and go to page.
- Ink saved as PencilKit data plus `strokes.json`, the same strokes as open data (position, pressure, tilt, time per point) for desktop Nexus to redraw.

## Building

There is no Mac in the loop: every push to `main` builds the app on a GitHub-hosted Mac (`.github/workflows/build.yml`). The project file is generated from `project.yml` with XcodeGen, and the build is unsigned. The newest build is always at **Releases › latest › NexusMobile.ipa**.

## Installing

Install `NexusMobile.ipa` on the iPad with [Sideloadly](https://sideloadly.io) on Windows, signed with a free Apple ID (a spare one is best). Free signing lasts 7 days; Sideloadly renews it automatically when the iPad is awake on the same Wi-Fi as the PC running it.
