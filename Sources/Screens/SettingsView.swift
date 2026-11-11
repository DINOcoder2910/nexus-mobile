import SwiftUI
import UniformTypeIdentifiers
import NexusCore

/// Settings: which data folder the app reads, and what it found there.
struct SettingsView: View {
    @Environment(NexusStore.self) private var store
    @State private var picking = false
    @State private var confirmSample = false

    var body: some View {
        let s = store.snapshot
        Form {
            Section {
                LabeledContent("Folder", value: store.folderName)
                if s.isDataFolder {
                    LabeledContent("Workstreams", value: "\(s.workstreams.count) in \(s.groups.count) groups")
                    LabeledContent("Tasks", value: "\(store.planning.open.count) open")
                    LabeledContent("Read", value: s.loadedAt.formatted(date: .omitted, time: .standard))
                } else {
                    Text("No Nexus data folder here yet (it needs a nexus.yaml).").foregroundStyle(.secondary)
                }
                if let why = s.readOnlyReason { Label(why, systemImage: "lock").foregroundStyle(.secondary) }
                Button("Read the folder again") { store.reload() }
            } header: { Text("Data folder") } footer: {
                Text("Nexus on the iPad works on the same plain files as on the laptop. Every change is a small edit to one tasks.yaml, so the laptop sees exactly what changed.")
            }

            Section {
                Button("Use a folder from Files…") { picking = true }
                if store.pickedFolder { Button("Go back to On My iPad › Nexus › nexus-data") { store.useDefaultFolder() } }
                if !s.isDataFolder && !store.pickedFolder { Button("Fill it with sample data to try the app") { confirmSample = true } }
            } footer: {
                Text("Sync (below) keeps this folder the same as the laptop's through the hub on the G14. You can also copy a data folder into On My iPad › Nexus › nexus-data with the Files app, or pick a folder another app keeps in sync.")
            }

            SyncSettings()

            if !s.problems.isEmpty {
                Section("Things to check") {
                    ForEach(s.problems) { p in
                        VStack(alignment: .leading) {
                            Text(p.file).font(.callout.monospaced())
                            Text(p.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?")
                LabeledContent("Day starts at", value: "\(Days.dayStartHour):00")
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.useFolder(url) }
        }
        .confirmationDialog("Make a sample data folder here?", isPresented: $confirmSample) {
            Button("Make sample data") { store.makeSample() }
        } message: { Text("It writes a few example workstreams and tasks into \(store.folderName). It never overwrites a file.") }
    }
}

/// What the app shows before it has a data folder.
struct FolderSetupView: View {
    @Environment(NexusStore.self) private var store
    @State private var picking = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 54)).foregroundStyle(.secondary)
            Text("No data folder yet").font(.title.weight(.semibold))
            Text("Nexus reads your plain files: the same data folder as on the laptop. Turn on **Sync** in Settings to download it from your hub, put a copy in **On My iPad › Nexus › nexus-data** with the Files app, pick a folder from Files, or try it with sample data first.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            HStack(spacing: 12) {
                Button("Try with sample data") { store.makeSample() }.buttonStyle(.borderedProminent)
                Button("Use a folder from Files…") { picking = true }.buttonStyle(.bordered)
                Button("Look again") { store.reload() }.buttonStyle(.bordered)
            }
            Text("Looking in: \(store.folderName)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Nexus")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.useFolder(url) }
        }
    }
}
