import SwiftUI
import UIKit
import NexusCore

/// Sync with the hub on the G14 (the Nexus repo's docs/sync.md). While the app is open it runs NexusCore's SyncClient in a loop:
/// a cycle (send this iPad's changes, then take everyone else's), then a long poll to the hub, woken early when the app
/// writes a file or the 3-second check sees one change. Going to the background it finishes what is pending, then stops.
/// The settings live in UserDefaults, the token in the Keychain, and the sync state in Application Support.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case off
        case notSetUp
        case connecting
        case upToDate
        case syncing(Int)
        case offline
        case problem(String)
        case paused([String])
        case choose(FirstSyncSummary)
        case notDataFolder
        case hubEmpty
    }

    private enum Keys {
        static let hub = "sync.hubAddress"
        static let device = "sync.deviceName"
        static let enabled = "sync.enabled"
        static let last = "sync.lastSynced"
        static let token = "hub-token"
    }

    private(set) var hubAddress: String
    private(set) var token: String
    private(set) var deviceName: String
    private(set) var enabled: Bool
    private(set) var status: Status = .off
    private(set) var lastSynced: Date?
    private(set) var conflictCopies: [String] = []
    private(set) var problems: [SyncProblem] = []
    /// The name of the folder "Use the hub's copy" moved this iPad's files to.
    private(set) var movedAside: String?
    /// One of the user's choices is being carried out.
    private(set) var working = false
    /// While offline: the changes here the hub hasn't got (the chip's "Offline · N waiting").
    private(set) var waitingHere = 0
    /// Which hub answered last: "rust" for the Rust hub, nil for the Node hub.
    private(set) var hubImpl: String?
    /// `-NexusTestSyncChip <state>` (UITests/SyncChipTests): the chip as it would be, with no hub.
    private let testChip: SyncChip? = SyncService.testChipFromLaunch()

    @ObservationIgnored private weak var store: NexusStore?
    @ObservationIgnored private var client: SyncClient?
    @ObservationIgnored private var clientKey = ""
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var waiting: Task<Void, Never>?
    @ObservationIgnored private var pendingRestart: Task<Void, Never>?
    @ObservationIgnored private var woken = false
    /// What the app wrote since the last cycle, when every writer named it (a board's folder); `everywhere` when one didn't.
    @ObservationIgnored private var touched: Set<String> = []
    @ObservationIgnored private var everywhere = true
    @ObservationIgnored private var active = true
    @ObservationIgnored private var cycling = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var presenceTransport: HTTPSyncTransport?

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: c)
    }()

    init() {
        let d = UserDefaults.standard
        hubAddress = d.string(forKey: Keys.hub) ?? ""
        deviceName = d.string(forKey: Keys.device) ?? Device.name
        enabled = d.bool(forKey: Keys.enabled)
        token = Keychain.get(Keys.token) ?? ""
        lastSynced = d.object(forKey: Keys.last) as? Date
        // any window's store (or the shortcuts) wrote to the folder: send it soon
        NotificationCenter.default.addObserver(forName: NexusStore.wrote, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self else { return }
                // paths are relative to the writer's folder: used only when it is the folder this syncs
                let named = n.userInfo?["touched"] as? [String]
                let same = (n.object as? NexusStore).map { $0.folder.standardizedFileURL == self.store?.folder.standardizedFileURL } ?? false
                self.wake(touched: same ? named : nil)
            }
        }
        // another folder was picked in a window: start again on it (once the shared store has moved to it too)
        NotificationCenter.default.addObserver(forName: NexusStore.folderChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        }
    }

    var isSetUp: Bool { HTTPSyncTransport.hubURL(hubAddress) != nil && !cleanToken.isEmpty }
    var canMoveAside: Bool { !(store?.pickedFolder ?? false) }
    private var cleanToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanDevice: String {
        let n = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? Device.name : n
    }

    // MARK: settings

    func attach(_ store: NexusStore) {
        guard self.store !== store else { return }
        self.store = store
        store.onWrite = { paths in _ = Task { @MainActor in self.wake(touched: paths) } }
        restart()
    }

    func setHubAddress(_ s: String) {
        hubAddress = s
        UserDefaults.standard.set(s, forKey: Keys.hub)
        settingsChanged()
    }

    func setToken(_ s: String) {
        token = s
        Keychain.set(s.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.token)
        settingsChanged()
    }

    func setDeviceName(_ s: String) {
        deviceName = s
        UserDefaults.standard.set(s, forKey: Keys.device)
        settingsChanged()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Keys.enabled)
        restart()
    }

    /// Typing in a field restarts sync once the typing pauses.
    private func settingsChanged() {
        pendingRestart?.cancel()
        pendingRestart = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { self.restart() }
        }
    }

    // MARK: running

    /// Starts (or starts again) with the current settings and data folder.
    func restart() {
        everywhere = true // whatever happened while stopped is looked for
        loop?.cancel()
        loop = nil
        waiting?.cancel()
        guard enabled else { status = .off; LivePresence.shared.stop(); return }
        guard let store, let url = HTTPSyncTransport.hubURL(hubAddress), !cleanToken.isEmpty else { status = .notSetUp; return }
        let key = Self.folderKey(store.folder) + "|" + url.absoluteString
        let full = key + "|" + cleanToken + "|" + cleanDevice
        if client == nil || clientKey != full {
            let transport = HTTPSyncTransport(base: url, token: cleanToken, device: cleanDevice, session: Self.session,
                                              appInfo: HTTPSyncTransport.appInfo(build: LivePresence.build))
            client = SyncClient(folder: store.folder, stateURL: Self.stateURL(key), hubUrl: url.absoluteString, transport: transport)
            presenceTransport = transport
            clientKey = full
            conflictCopies = []
            problems = []
            failures = 0
        }
        if status == .off || status == .notSetUp { status = .connecting }
        guard active else { return }
        if let presenceTransport { LivePresence.shared.start(presenceTransport) }
        loop = Task { await self.run() }
    }

    /// Something changed here (the app wrote a file, or the folder changed underneath): sync soon. `touched`: the paths written,
    /// relative to the folder, when the writer named them all; nil, and the next cycle looks over the whole folder.
    func wake(touched paths: [String]? = nil) {
        if let paths { touched.formUnion(paths) } else { everywhere = true }
        guard enabled else { return }
        woken = true
        waiting?.cancel()
        if loop == nil && active { restart() }
    }

    func syncNow() {
        if loop == nil { restart() } else { wake() }
    }

    func becameActive() {
        active = true
        if loop == nil { restart() } else { wake() }
    }

    /// Going to the background: finish sending what is pending (iOS gives a little time), then stop until the app is back.
    func enteredBackground() {
        active = false
        loop?.cancel()
        loop = nil
        waiting?.cancel()
        LivePresence.shared.stop()
        guard enabled, let client else { return }
        let box = BackgroundTask()
        let hints = takeHints()
        let work = Task { () -> Void in
            await Self.hand(hints, to: client)
            _ = try? await client.cycle()
        }
        box.id = UIApplication.shared.beginBackgroundTask(withName: "Nexus sync") {
            MainActor.assumeIsolated {
                work.cancel()
                box.end()
            }
        }
        Task {
            await work.value
            box.end()
        }
    }

    /// iOS woke the app in the background: one cycle, so reminders see what changed on the laptop.
    /// (The client takes one cycle at a time, so this waits for the loop's own if one is running.)
    func backgroundCycle(_ shared: NexusStore) async {
        if store == nil { attach(shared) } // launched straight into the background: no window attached it yet
        guard enabled, let client else { return }
        await Self.hand(takeHints(), to: client)
        if case .synced(let r)? = try? await client.cycle() {
            lastSynced = Date()
            UserDefaults.standard.set(lastSynced, forKey: Keys.last)
            if !r.pulled.isEmpty {
                store?.reload()
                NotificationCenter.default.post(name: NexusStore.readAgain, object: store)
            }
        }
    }

    private enum Next {
        case longPoll
        case after(Double)
    }

    private func run() async {
        while !Task.isCancelled {
            woken = false
            let next = await runCycle()
            if Task.isCancelled { return }
            if !woken {
                switch next {
                case .longPoll:
                    guard let client else { return }
                    // the Rust hub's change feed tells the moment something changes, so a cycle every 5 minutes is only the backstop;
                    // the long poll of the Node hub comes back every 25 s
                    let feeds = await client.followsFeed
                    let seconds = feeds ? 300 : 25
                    await waitFor { _ = try await client.waitForHub(seconds: seconds) }
                case .after(let seconds):
                    await waitFor { try await Task.sleep(for: .seconds(seconds)) }
                }
            }
            if Task.isCancelled { return }
            // a board saves soon after each stroke and each save wakes sync: gather a couple of seconds of them into one cycle (a cycle
            // looks at the board's folder only, but each one still asks the hub)
            if woken { try? await Task.sleep(for: .seconds(2)) }
        }
    }

    /// What the app wrote since the last cycle, handed to the client once (nil: anything may have changed).
    private func takeHints() -> [String]? {
        defer { touched = []; everywhere = false }
        return everywhere ? nil : Array(touched)
    }

    private static func hand(_ hints: [String]?, to client: SyncClient) async {
        await client.useQuickScans()
        if let hints { await client.changed(hints) } else { await client.changedEverywhere() }
    }

    /// Runs `op` until it ends, `wake()` cancels it, or the loop is cancelled.
    private func waitFor(_ op: @escaping @Sendable () async throws -> Void) async {
        let t = Task { _ = try? await op() }
        waiting = t
        await withTaskCancellationHandler {
            await t.value
        } onCancel: {
            t.cancel()
        }
        waiting = nil
    }

    private func runCycle() async -> Next {
        guard let client else { return .after(60) }
        HangWatch.note("sync: cycle starts")
        defer { HangWatch.note("sync: cycle ends") }
        cycling = true
        defer { cycling = false }
        await Self.hand(takeHints(), to: client)
        do {
            let outcome = try await client.cycle(progress: { p in _ = Task { @MainActor in self.showProgress(p) } })
            failures = 0
            waitingHere = 0
            hubImpl = await client.hubImpl
            switch outcome {
            case .synced(let r):
                conflictCopies = r.conflictCopies
                problems = Array(Set(r.problems)).sorted { $0.path < $1.path }
                status = .upToDate
                let now = Date()
                lastSynced = now
                UserDefaults.standard.set(now, forKey: Keys.last)
                if !r.pulled.isEmpty {
                    store?.reload()
                    NotificationCenter.default.post(name: NexusStore.readAgain, object: store) // the windows read it too
                    NotificationCenter.default.post(name: LivePresence.pulled, object: r.pulled) // an open board reads them now
                }
                return .longPoll
            case .notADataFolder:
                status = .notDataFolder
                return .after(30)
            case .hubEmpty:
                status = .hubEmpty
                return .after(60)
            case .needsFirstSyncChoice(let s):
                status = .choose(s)
                return .after(600)
            case .pausedForDeletions(let paths):
                status = .paused(paths)
                return .after(600)
            }
        } catch is CancellationError {
            return .after(1)
        } catch let e as SyncError {
            if e.isTransient {
                failures += 1
                if case .offline = e {
                    status = .offline
                    waitingHere = await client.waitingHere()
                } else {
                    status = .problem(e.plainWords)
                }
                return .after(min(60, pow(2, Double(failures))))
            }
            status = .problem(e.plainWords)
            return .after(60)
        } catch {
            status = .problem(error.localizedDescription)
            return .after(60)
        }
    }

    private func showProgress(_ p: SyncProgress) {
        guard cycling, p.remaining > 0 else { return }
        status = .syncing(p.remaining)
    }

    // MARK: the user's choices

    /// First sync: move this iPad's folder aside and download everything from the hub.
    func useHubCopy() {
        guard let client else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let moved = try await client.useHubCopy()
                movedAside = moved?.lastPathComponent
                status = .connecting
                store?.reload()
                NotificationCenter.default.post(name: NexusStore.readAgain, object: store)
                wake()
            } catch {
                status = .problem(Self.words(error))
            }
        }
    }

    /// First sync: keep both sides' files; where a file differs, this iPad's version becomes a conflict copy.
    func mergeWithThisIPad() {
        guard let client else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await client.mergeWithHub()
                status = .connecting
                wake()
            } catch {
                status = .problem(Self.words(error))
            }
        }
    }

    /// After a pause: the files really were deleted here, so delete them on the hub (and the laptop) too.
    func deleteOnHubToo() {
        guard let client else { return }
        Task {
            await client.allowPendingDeletions()
            status = .connecting
            wake()
        }
    }

    /// After a pause: download the missing files again.
    func bringBack() {
        guard let client else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let back = try await client.bringBackDeleted()
                if !back.isEmpty { store?.reload(); NotificationCenter.default.post(name: NexusStore.readAgain, object: store) }
                status = .connecting
                wake()
            } catch {
                status = .problem(Self.words(error))
            }
        }
    }

    // MARK: wording

    var statusText: String {
        switch status {
        case .off: return "Off"
        case .notSetUp: return "Add the hub's address and token"
        case .connecting: return "Connecting…"
        case .upToDate: return "Up to date"
        case .syncing(let n): return n == 1 ? "Syncing 1 file" : "Syncing \(n) files"
        case .offline: return "Offline, retrying"
        case .problem(let why): return why
        case .paused(let paths): return "Paused: \(paths.count) files would be deleted"
        case .choose: return "Waiting for you to choose how to start"
        case .notDataFolder: return "Waiting: this folder has no nexus.yaml"
        case .hubEmpty: return "The hub is empty. Sync the laptop with it first."
        }
    }

    var statusColor: Color {
        switch status {
        case .upToDate: return Theme.planned
        case .problem, .paused, .notDataFolder: return Theme.late
        case .offline, .choose, .hubEmpty: return Theme.soon
        default: return .secondary
        }
    }

    /// The sync chip (the iPad's sidebar foot, the top of the iPhone's More), in the laptop's words (NexusCore SyncChip).
    var chip: SyncChip {
        if let testChip { return testChip }
        let state: SyncChip.State
        switch status {
        case .off: state = .off
        case .notSetUp: state = .notSetUp
        case .connecting: state = .connecting
        case .upToDate: state = .inSync
        case .syncing(let n): state = .syncing(n)
        case .offline: state = .offline
        case .problem(let why): state = .problem(why)
        case .paused(let paths): state = .deletionsHeld(paths.count)
        case .choose: state = .waiting("Waiting for you to choose how to start, in Settings › Sync.")
        case .notDataFolder: state = .waiting("This folder has no nexus.yaml.")
        case .hubEmpty: state = .waiting("The hub is empty. Sync the laptop with it first.")
        }
        return SyncChip.of(state, waiting: waitingHere, conflicts: conflictCopies.count, lastSynced: lastSynced)
    }

    /// `-NexusTestSyncChip insync|syncing|offline|conflicts|problem` (UITests/SyncChipTests).
    nonisolated private static func testChipFromLaunch() -> SyncChip? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-NexusTestSyncChip"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "insync": return SyncChip.of(.inSync, lastSynced: Date().addingTimeInterval(-120))
        case "syncing": return SyncChip.of(.syncing(3))
        case "offline": return SyncChip.of(.offline, waiting: 3)
        case "conflicts": return SyncChip.of(.inSync, conflicts: 2)
        case "problem": return SyncChip.of(.problem("The hub didn't accept the token. Copy it again from the hub."))
        default: return nil
        }
    }

    private static func words(_ error: Error) -> String {
        (error as? SyncError)?.plainWords ?? error.localizedDescription
    }

    // MARK: where the state lives

    /// The data folder as a key that survives app updates (the app's container path changes when a new build is installed).
    static func folderKey(_ folder: URL) -> String {
        let docs = FolderAccess.documents.standardizedFileURL.path
        let path = folder.standardizedFileURL.path
        if path.hasPrefix(docs + "/") { return "documents:" + String(path.dropFirst(docs.count + 1)) }
        return path
    }

    static func stateURL(_ key: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent(SyncState.fileName(forKey: key))
    }
}

/// A background task iOS lets the app finish after it leaves the screen.
@MainActor
private final class BackgroundTask {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
