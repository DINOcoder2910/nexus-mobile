import AppIntents

// The Live Activity's buttons. Built into the app and the extension (project.yml): the extension needs the types for its buttons,
// and iOS runs a LiveActivityIntent's perform in the app's own process (woken in the background), so only the app's copy does the
// work (NEXUS_WIDGET is set for the extension).

/// Stop for the running timer on the Live Activity: the timer stops as the app's Stop does.
struct StopTimerLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop the Nexus timer"
    static let description = IntentDescription("Stops the time tracking timer that runs in Nexus.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !NEXUS_WIDGET
        await LiveActivities.stopTimer()
        #endif
        return .result()
    }
}

/// Stop for a recording on the Live Activity: the recording is saved and turned into words, as the app's Stop does.
struct StopRecordingLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop the Nexus recording"
    static let description = IntentDescription("Stops the class or meeting Nexus is recording, and keeps it.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !NEXUS_WIDGET
        await LiveActivities.stopRecording()
        #endif
        return .result()
    }
}

/// Pin while recording, on the Live Activity: this moment is pinned as Important, as the recording bar's button does.
struct PinMomentLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pin this moment in the Nexus recording"
    static let description = IntentDescription("Pins the moment as Important in the recording Nexus is making.")
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !NEXUS_WIDGET
        await LiveActivities.pinMoment()
        #endif
        return .result()
    }
}

/// Start on the next task: a time now and the timer on it, as Today's Next up does.
struct StartTaskLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start the Nexus timer on the next task"
    static let description = IntentDescription("Starts the time tracking timer on the task Nexus has up next.")
    static let isDiscoverable = false

    @Parameter(title: "Task") var task: String

    init() { task = "" }
    init(task: String) { self.task = task }

    func perform() async throws -> some IntentResult {
        #if !NEXUS_WIDGET
        await LiveActivities.startTask(task)
        #endif
        return .result()
    }
}

/// The tick on the card: the task is done (its timer stops), as its tick in the app does.
struct DoneTaskLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Tick off the Nexus task"
    static let description = IntentDescription("Ticks off the task the Nexus Live Activity shows.")
    static let isDiscoverable = false

    @Parameter(title: "Task") var task: String

    init() { task = "" }
    init(task: String) { self.task = task }

    func perform() async throws -> some IntentResult {
        #if !NEXUS_WIDGET
        await LiveActivities.tickTask(task)
        #endif
        return .result()
    }
}
