import SwiftUI

/// How Nexus works: the laptop's guide (its F1, `docs/guide.md`) in the iPhone's and the iPad's words, one section at a time. Each
/// device's own way in (the tab bar, the sidebar) is told first; the rest is the same app on both. Keep it true when a feature changes.
struct GuideView: View {
    struct Part: Identifiable {
        let id: String
        let title: String
        let icon: String
        let text: String
    }

    static var parts: [Part] {
        let phone = Device.isPhone
        return [
            Part(id: "files", title: "Your files", icon: "folder", text: """
            Nexus works on plain files you own: one data folder, the same on the laptop, the iPad and the iPhone. Tasks are YAML, notes are markdown, a board is a folder of ink, text and pictures, and any PDF or document can sit beside them. Sync through the hub on the G14 keeps every device's copy the same; it works offline and catches up when it can reach the hub.
            """),
            Part(id: "around", title: "Getting around", icon: phone ? "rectangle.split.1x2" : "sidebar.left", text: phone ? """
            The tab bar holds what you use most: **Today**, **Calendar**, the **Inbox**, your **Notebooks**, and **More**, which lists every place in Nexus (Home, the Planner, Tasks, Study, Ideas, Claude, each workstream, Files, Settings, this guide). The round **+** adds a task wherever you are. Less-used things sit in **⋯** menus and in what you get by holding a row.
            """ : """
            The sidebar lists every place: Home, Today, the Planner, the Calendar, Tasks, Study, Ideas, Claude, your workstreams by group, the Inbox and Someday, your notebooks, Files and Settings. With a keyboard, hold **⌘** to see the keys (⌘1 to ⌘6 for the main places, ⌘N for a new task). New windows come from holding the app's icon; a board's menu has **Open in a new window**.
            """),
            Part(id: "home", title: "Home and Today", icon: "house", text: """
            **Home** says where the day stands: what is planned and due, the day brief with **Plan with Claude**, key dates ★ with their countdown, the Inbox while something is in it (with **File my Inbox**), and the figures for what slipped, what you're waiting on and your workstreams (tap one to go there). **Today** is the plan itself: timed things first, repeats, deadlines that need you, what slipped (move it to today in one go) and tomorrow.
            """),
            Part(id: "tasks", title: "Tasks", icon: "checklist", text: """
            Add a task with **+**, typed the way the laptop reads it: `physics sheet by fri 45m #physics !` gives it a deadline, an estimate, a workstream and a ★. Tap a task for its panel, where everything can be changed: the title, ★, the deadline, the days and times it is planned, the estimate, subtasks, waiting on, repeats, tags, the note and Someday. Hold a task for its menu. Tick it with its ring; **Undo** is on the bar that shows after every change.
            """),
            Part(id: "plan", title: "Planner and Calendar", icon: "calendar", text: """
            The **Planner** shows 3 days or a week with the task bank below: drag a task onto a day\(phone ? " (hold it first)" : ""). The **Calendar** shows your calendars (whatever accounts are added in the iOS Settings app) with the tasks planned at a time and the deadlines, as Day, 3 days, Week, Month or List. Double-tap an empty time for a new event; drag a task's block to move it; **Place tasks** lists what still needs a time.
            """),
            Part(id: "boards", title: "Notebooks and boards", icon: "scribble.variable", text: phone ? """
            A board is an endless page: your finger draws, two fingers scroll and zoom, the hand scrolls with one finger. The bar's **⋯** holds the Tools panel, the tutor, recording, read aloud, links, the background and zoom. Tap the board's name for **Split screen**: Today, the Calendar, another board or a PDF under the board, with a divider to drag. Hold a board in its notebook to rename, move, duplicate or share it as a PDF.
            """ : """
            A board is an endless page: the Pencil writes, fingers scroll and pick things (or turn on **Fingers draw too**). Hold the Pencil still at the end of a stroke to snap it to a shape. PDFs, pictures, typed blocks and the Study tools go on it from **+** and **Tools**. Tap the board's name for **Side by side**: Today, the Calendar, another board or a PDF beside it. **Search boards** finds handwriting and typed words.
            """),
            Part(id: "claude", title: "Claude", icon: "sparkles", text: phone ? """
            The **Claude** row in More, or ✦ on Today, **Ask Claude** on a task and a workstream's **⋯**, opens the conversation. Claude reads your data folder and proposes each change as a card to **Accept** or **Reject**; nothing is written without your Accept. The model, New conversation and Earlier conversations are behind **⋯**, the commands behind **/**. The Plan / API chip says which Claude answers.
            """ : """
            **✦** in any screen's toolbar opens the conversation beside it; the sidebar's **Claude** row shows it full width. Claude reads your data folder and proposes each change as a card to **Accept** or **Reject**; nothing is written without your Accept. The model menu, the commands and the Plan / API chip are in view.
            """),
            Part(id: "study", title: "Study", icon: "rectangle.on.rectangle.angled", text: """
            Decks from every workstream's `study/decks` folder, reviewed with the laptop's scheduling: flip and grade, type the answer, or multiple choice. Every grade is saved at once and counts on every device.
            """),
            Part(id: "fileslist", title: "Files", icon: "doc.on.doc", text: """
            **Files** is the data folder as it is on disk. Open any PDF, picture, Word, Excel or PowerPoint file, text or YAML; a folder opens in place and a board opens as a board. Hold a file to share, rename or delete it (it goes to the bin, `.trash`); **+** makes a folder or brings files in from the Files app. The files Nexus is built on, and boards, are renamed and deleted from their own screens, so they show a lock here.
            """),
            Part(id: "share", title: "From other apps", icon: "square.and.arrow.down", text: """
            Say **“Add to Nexus”** to Siri, or put **Add to Nexus** on the Action button, and the line lands as if typed. **Share into Nexus** from Safari, Photos, Files or Mail through a Shortcut (Settings › Share into Nexus shows how to make it, once): a PDF or a photo becomes a board in the notebook Shared, a link or words a task in the Inbox. Tasks, workstreams and boards show up in Spotlight. **Reminders** come for what is due, before a task planned at a time and before events.
            """),
            Part(id: "laptop", title: "Only on the laptop", icon: "laptopcomputer", text: """
            Customize (changing Nexus itself), the terminal, the backup of the data folder and calendar accounts stay on the laptop: they need its files, its git and its sign-ins.
            """),
        ]
    }

    var body: some View {
        List {
            ForEach(Self.parts) { p in
                Section {
                    Text(.init(p.text)).font(.nx(.callout)).fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label(p.title, systemImage: p.icon).font(.nx(.subheadline, .semibold))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("How Nexus works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
