import AppIntents

// The Live Activity's buttons. Built into the app and the extension (project.yml): the extension needs the types for its buttons,
// and iOS runs a LiveActivityIntent's perform in the app's own process (woken in the background), so only the app's copy does the
// work (NEXUS_WIDGET is set for the extension).

/// Stop on the timer's Live Activity: the timer stops as the app's Stop does, and the activity goes.
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

/// Stop on a recording's Live Activity: the recording is saved and turned into words, as the app's Stop does.
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

/// Pin on a recording's Live Activity: this moment is pinned as Important, as the recording bar's button does.
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
