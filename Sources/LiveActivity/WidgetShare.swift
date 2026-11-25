import SwiftUI
import WidgetKit
import NexusCore

/// The Home Screen widgets' card (NexusWidgetShare in NexusActivity.swift): the day as the Live Activity shows it, written into the data
/// folder's `widgets/<device>.json` whenever it changes (a tick, a timer started or stopped, the next task changing), so sync takes it
/// to the hub, where the widget reads it. Only a change is written: a running clock counts in the widget by itself, so its seconds
/// don't make a new file (and no backup commit).
@MainActor
enum WidgetShare {
    /// Turned on once a widget key has been copied (Settings › Lock Screen › Home Screen widgets): until then nothing is written.
    static let settingKey = "widgets.on"
    static var on: Bool { UserDefaults.standard.bool(forKey: settingKey) }
    private static var lastSignature = ""
    private static var reload: Task<Void, Never>?

    static func update(now: Date = Date()) {
        guard on else { return }
        let store = AppServices.store
        guard store.snapshot.isDataFolder, store.snapshot.readOnlyReason == nil, let found = LiveActivities.state(now: now, always: true) else { return }
        let state = found.0
        let sig = signature(state, now: now)
        guard sig != lastSignature else { return }
        let url = store.folder.appendingPathComponent(NexusWidgetShare.path(device: Device.name))
        // the file already says this (the app started again): nothing to write
        if let old = try? FolderAccess.read(url), let f = try? NexusWidgetShare.decoder.decode(NexusWidgetShare.File.self, from: Data(old.utf8)),
           signature(f.state, now: now) == sig {
            lastSignature = sig
            return
        }
        let file = NexusWidgetShare.File(device: Device.name, updated: now, state: state)
        guard let data = try? NexusWidgetShare.encoder.encode(file) else { return }
        do {
            try FolderAccess.write(url, String(decoding: data, as: UTF8.self) + "\n")
            lastSignature = sig
            store.didWrite(touched: [NexusWidgetShare.path(device: Device.name)])
        } catch { return }
        // the widgets read again once sync has had time to take the file to the hub
        reload?.cancel()
        reload = Task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    /// What the card says, without what only the passing of time changes: the tracked time counts on from a fixed start while a timer
    /// runs, so `tracked` and `stamp` are folded into that start (to the minute).
    static func signature(_ s: NexusLiveState, now: Date) -> String {
        var t = s
        if s.counting {
            t.tracked = (s.stamp.timeIntervalSince1970 - s.tracked).rounded() / 60
            t.stamp = Date(timeIntervalSince1970: 0)
        } else {
            t.tracked = (s.tracked / 60).rounded()
            t.stamp = Date(timeIntervalSince1970: 0)
        }
        return (try? NexusWidgetShare.encoder.encode(t)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// The widget key for Settings: this device's hub address and token and its card's name; nil until sync is set up.
    static var key: String? {
        guard let h = HubAsk.hub else { return nil }
        return NexusWidgetShare.Key(hub: h.url.absoluteString, token: h.token, device: Device.name).text
    }
}

/// Settings › Lock Screen › Home Screen widgets: how to add one, and the widget key to paste into it.
struct WidgetSettings: View {
    @AppStorage(WidgetShare.settingKey) private var on = false
    @State private var copied = false

    var body: some View {
        if LiveActivities.supported {
            Section {
                if let key = WidgetShare.key {
                    Button {
                        UIPasteboard.general.string = key
                        on = true
                        copied = true
                        WidgetShare.update()
                    } label: {
                        Label(copied ? "Widget key copied" : "Copy the widget key", systemImage: copied ? "checkmark" : "key")
                    }
                    .accessibilityIdentifier("widget-copy-key")
                    if on {
                        Toggle("Keep the widgets up to date", isOn: $on)
                            .accessibilityIdentifier("widget-on")
                    }
                } else {
                    Label("Set up sync with the hub first (Settings › Sync): the widgets read your day from it.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Home Screen widgets") } footer: {
                Text("Touch and hold the Home Screen, tap Edit › Add Widget, pick Nexus, then hold the widget › Edit Widget and paste the key once. The widget shows the same card as the Lock Screen, from the hub, and updates when this \(Device.name) syncs. The key holds your hub's token: paste it only there.")
            }
        }
    }
}
