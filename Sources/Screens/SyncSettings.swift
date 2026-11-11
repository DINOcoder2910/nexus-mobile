import SwiftUI
import NexusCore

/// Settings › Sync: the hub's address and token, this iPad's name, on and off, where things stand, and the questions sync
/// asks (how to start the first time, files that would be deleted). The sections sit inside SettingsView's Form.
struct SyncSettings: View {
    @Environment(SyncService.self) private var sync

    var body: some View {
        Section {
            LabeledContent("Hub address") {
                TextField("Hub address", text: Binding(get: { sync.hubAddress }, set: { sync.setHubAddress($0) }),
                          prompt: Text("http://100.x.y.z:8743"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Hub token") {
                SecureField("Hub token", text: Binding(get: { sync.token }, set: { sync.setToken($0) }), prompt: Text("Paste it here"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("This device's name") {
                TextField("This device's name", text: Binding(get: { sync.deviceName }, set: { sync.setDeviceName($0) }), prompt: Text("iPad"))
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Sync with the hub", isOn: Binding(get: { sync.enabled }, set: { sync.setEnabled($0) }))
            if sync.enabled {
                LabeledContent("Status") {
                    Text(sync.statusText).foregroundStyle(sync.statusColor).multilineTextAlignment(.trailing)
                }
                if let last = sync.lastSynced {
                    LabeledContent("Last synced") { Text(last, format: .relative(presentation: .named)) }
                }
                Button("Sync now") { sync.syncNow() }.disabled(!sync.isSetUp)
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Keeps this iPad's data folder the same as the laptop's, through the hub on the G14. The address and token come from the hub's first start (Tailscale's address works anywhere, the home network's at home). The device name goes into the name of a conflict copy made from this iPad.")
        }

        if let moved = sync.movedAside {
            Section {
                Label("This iPad's old files are in On My iPad › Nexus › \(moved).", systemImage: "folder")
                    .foregroundStyle(.secondary)
            }
        }

        switch sync.status {
        case .choose(let s): firstSync(s)
        case .paused(let paths): paused(paths)
        case .notDataFolder: missingFolder
        default: EmptyView()
        }

        if !sync.conflictCopies.isEmpty {
            Section {
                ForEach(sync.conflictCopies, id: \.self) { path in
                    Text(path).font(.callout.monospaced()).textSelection(.enabled)
                }
            } header: {
                SectionTitle(title: "Conflict copies", count: sync.conflictCopies.count)
            } footer: {
                Text("When the same lines changed on two devices, the hub keeps one version and saves the other beside it with “(conflict …)” in its name. Open both, keep what you want, then delete the copy.")
            }
        }

        if !sync.problems.isEmpty {
            Section {
                ForEach(sync.problems, id: \.self) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.path).font(.callout.monospaced())
                        Text(p.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                SectionTitle(title: "Not synced", count: sync.problems.count)
            }
        }
    }

    private func firstSync(_ s: FirstSyncSummary) -> some View {
        Section {
            Text(summary(s))
            if sync.canMoveAside {
                Button { sync.useHubCopy() } label: {
                    choice("Use the hub's copy (recommended)",
                           "Moves this iPad's folder aside to “nexus-data before sync …” in On My iPad › Nexus (nothing is deleted), then downloads everything from the hub.")
                }
                .disabled(sync.working)
            }
            if s.localIsDataFolder {
                Button { sync.mergeWithThisIPad() } label: {
                    choice("Merge with this iPad's files",
                           "Files only on this iPad go to the hub. Where a file differs, this iPad takes the hub's version and keeps its own beside it as a conflict copy.")
                }
                .disabled(sync.working)
            }
            if !sync.canMoveAside && !s.localIsDataFolder {
                Text("This folder was picked from Files and isn't a Nexus data folder. Empty it in Files, or go back to On My iPad › Nexus › nexus-data, to download the hub's copy.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("How to start syncing")
        }
    }

    private func paused(_ paths: [String]) -> some View {
        Section {
            Text("\(paths.count) files are gone from this iPad's folder. Sync stopped so they aren't deleted on the hub and the laptop too.")
            Button("Bring them back from the hub") { sync.bringBack() }.disabled(sync.working)
            Button("Delete them everywhere", role: .destructive) { sync.deleteOnHubToo() }.disabled(sync.working)
            DisclosureGroup("Show the files") {
                ForEach(paths, id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        } header: {
            Text("Paused: \(paths.count) files would be deleted")
        }
    }

    private var missingFolder: some View {
        Section {
            Text("The data folder has no nexus.yaml, so sync isn't changing anything (an empty or missing folder must never look like “everything was deleted”).")
            Button("Download the data folder from the hub") { sync.useHubCopy() }.disabled(sync.working)
        } footer: {
            Text("Anything still in the folder is moved aside first, into a folder named “… before sync” beside it.")
        }
    }

    private func choice(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func summary(_ s: FirstSyncSummary) -> String {
        var parts = ["This iPad's folder has \(s.localFiles) files and the hub has \(s.hubFiles)."]
        if s.differ > 0 { parts.append(s.differ == 1 ? "1 file is different." : "\(s.differ) files are different.") }
        if s.onlyHere > 0 { parts.append(s.onlyHere == 1 ? "1 file is only on this iPad." : "\(s.onlyHere) files are only on this iPad.") }
        if !s.localIsDataFolder { parts.append("This folder has no nexus.yaml, so it isn't a Nexus data folder.") }
        return parts.joined(separator: " ")
    }
}
