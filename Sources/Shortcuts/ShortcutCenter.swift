import SwiftUI
import NexusCore

/// The shortcuts of both devices, as Settings › Shortcuts shows them and the app runs them.
///
/// The iPad owns `shortcuts/ipad.yaml`: its list (ShortcutRegistry) with the keys the user chose, written whole whenever the list or a key
/// changes. The laptop may change a `keys:` line in it, which is read in when the folder is read again (the store looks every 3 s).
/// The laptop's `shortcuts/laptop.yaml` is read for the Laptop side; an edit there changes only that shortcut's `keys:` line.
/// The iPad's keys are also kept in the app (UserDefaults), so they work without a data folder or while its file doesn't parse.
@Observable
final class ShortcutCenter {
    static let shared = ShortcutCenter()
    /// Posted after the iPad's keys changed (the board's key commands and gestures follow).
    static let changed = Notification.Name("NexusShortcutsChanged")
    static let cacheKey = "shortcuts.ipad.yaml"

    enum Side: String, Hashable { case laptop, ipad }

    /// The iPad's shortcuts, with the keys in effect.
    private(set) var ipad: ShortcutFile
    /// Why the iPad's file is left alone (it doesn't parse, or a newer Nexus wrote it), or nil.
    private(set) var ipadNote: String?
    /// The laptop's shortcuts, or nil when its file isn't there or can't be read.
    private(set) var laptop: ShortcutFile?
    /// Why the laptop's file can't be shown or changed, or nil (nil with no file: it isn't there yet).
    private(set) var laptopNote: String?
    /// An edit that could not be saved.
    var problem: String?

    /// True while Settings › Shortcuts records a key: the app's own keys stand aside so the press reaches the recorder.
    var capturing = false
    /// Asks from a key that the screen it opens picks up (Search tasks, New notebook).
    var searchPending = false
    var notebookRequest = 0

    @ObservationIgnored var onWrite: (() -> Void)?
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var canWrite = false
    @ObservationIgnored private var ipadText: String?
    @ObservationIgnored private var laptopText: String?

    init() {
        let cached = UserDefaults.standard.string(forKey: ShortcutCenter.cacheKey).flatMap { try? ShortcutsYaml.parse($0) }
        ipad = ShortcutFile.merged(device: ShortcutRegistry.device, scopes: ShortcutRegistry.scopes, registry: ShortcutRegistry.all, existing: cached)
    }

    func file(_ side: Side) -> ShortcutFile? { side == .ipad ? ipad : laptop }
    func note(_ side: Side) -> String? { side == .ipad ? ipadNote : laptopNote }
    var laptopMissing: Bool { laptop == nil && laptopNote == nil }

    /// The iPad's bindings for a shortcut.
    func keys(_ id: String) -> [String] { ipad[id]?.keys ?? [] }

    /// The gesture row that has this gesture (nil: off).
    func action(forGesture g: String) -> String? {
        ipad.shortcuts.first { $0.kind == .gesture && $0.keys.contains { $0.caseInsensitiveCompare(g) == .orderedSame } }?.id
    }

    // MARK: reading

    var ipadPath: String { DataFolder.shortcutsFile("ipad") }
    var laptopPath: String { DataFolder.shortcutsFile("laptop") }

    /// Reads both files (after the store read the folder). Writes the iPad's when its list or keys differ from the file.
    func load(root: URL, canWrite: Bool) {
        let folderChanged = root != self.root
        self.root = root
        self.canWrite = canWrite
        if folderChanged { ipadText = nil; laptopText = nil }

        // the laptop's
        let lt = DataFolder.text(root, laptopPath)
        if lt == nil {
            laptop = nil; laptopNote = nil; laptopText = nil
        } else if lt != laptopText || folderChanged {
            laptopText = lt
            do {
                laptop = try ShortcutsYaml.parse(lt!)
                laptopNote = nil
            } catch {
                laptop = nil
                laptopNote = "shortcuts/laptop.yaml \(error), so the iPad leaves it alone."
            }
        }

        // the iPad's
        let onDiskText = DataFolder.text(root, ipadPath)
        if let t = onDiskText, t == ipadText, !folderChanged { return }
        ipadText = onDiskText
        guard let it = onDiskText else {
            ipadNote = nil
            if canWrite { save(ipad) }
            return
        }
        do {
            let onDisk = try ShortcutsYaml.parse(it)
            let merged = ShortcutFile.merged(device: ShortcutRegistry.device, scopes: ShortcutRegistry.scopes, registry: ShortcutRegistry.all, existing: onDisk)
            ipadNote = nil
            if merged != ipad {
                ipad = merged
                NotificationCenter.default.post(name: ShortcutCenter.changed, object: nil)
            }
            cache()
            if merged != onDisk, canWrite { save(merged) }
        } catch {
            ipadNote = "shortcuts/ipad.yaml \(error). The iPad keeps its own keys and won't write the file until it's fixed (or deleted)."
        }
    }

    // MARK: changing

    /// Puts a changed copy of one side's shortcuts into effect: the iPad's file is written whole, the laptop's gets one `keys:` line
    /// edit per shortcut that changed.
    func apply(_ side: Side, _ f: ShortcutFile) {
        switch side {
        case .ipad:
            guard f != ipad else { return }
            ipad = f
            NotificationCenter.default.post(name: ShortcutCenter.changed, object: nil)
            cache()
            if canWrite, ipadNote == nil { save(f) }
        case .laptop:
            guard let root, let old = laptop else { return }
            let changed = f.shortcuts.filter { s in old[s.id].map { $0.keys != s.keys } ?? false }
            guard !changed.isEmpty else { return }
            guard canWrite else { problem = "This data folder is read-only, so the laptop's shortcuts can't be changed here."; return }
            let url = root.appendingPathComponent(laptopPath)
            do {
                var text = try FolderAccess.read(url)
                for s in changed { text = try ShortcutsYaml.setKeys(text, id: s.id, keys: s.keys) }
                try FolderAccess.write(url, text)
                laptopText = text
                laptop = try ShortcutsYaml.parse(text)
                laptopNote = nil
                onWrite?()
            } catch {
                problem = "Couldn't change the laptop's shortcuts: \(error)"
            }
        }
    }

    private func cache() {
        UserDefaults.standard.set(ShortcutsYaml.write(ipad), forKey: ShortcutCenter.cacheKey)
    }

    private func save(_ f: ShortcutFile) {
        guard let root else { return }
        let text = ShortcutsYaml.write(f)
        guard text != ipadText else { return }
        do {
            try FolderAccess.write(root.appendingPathComponent(ipadPath), text)
            ipadText = text
            onWrite?()
        } catch {
            problem = "Couldn't save shortcuts/ipad.yaml: \(error.localizedDescription)"
        }
    }
}
