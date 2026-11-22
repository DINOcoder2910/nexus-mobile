import SwiftUI
import PhotosUI
import QuickLook
import ImageIO
import UniformTypeIdentifiers
import NexusCore

/// Drop: send files to your other devices, like AirDrop between your own (the laptop's docs/sync.md "Drop"). Anything in `Drop/` at
/// the data folder's top reaches the laptop, the G14 and the other iPad or iPhone through the hub; what came from another device
/// says which one (this device's record, NexusCore DropLog). Add from Photos, the Files app or the camera; tap to look, hold for
/// Share (Save Image, Save to Files, another app) and Delete. Files stay until you delete them. The Files app shows the same folder
/// (On My iPad › Nexus › nexus-data › Drop).
struct DropView: View {
    @Environment(NexusStore.self) private var store
    @Environment(SyncService.self) private var sync

    @State private var items: [DropRow] = []
    @State private var preview: URL?
    @State private var pickingPhotos = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var snapping = false
    @State private var deleting: DropRow?
    @State private var clearing = false
    @State private var busy = false
    /// What was new when the screen opened stays marked New while it is open.
    @State private var fresh: Set<String> = []

    private var dropURL: URL { store.folder.appendingPathComponent(DropFolder.folder, isDirectory: true) }

    var body: some View {
        List {
            Section {
                Button { pickingPhotos = true } label: { Label("Photos and videos", systemImage: "photo.on.rectangle") }
                    .accessibilityIdentifier("drop-photos")
                Button { importing = true } label: { Label("From the Files app", systemImage: "folder") }
                    .accessibilityIdentifier("drop-files")
                Button { snapping = true } label: { Label("Take a photo", systemImage: "camera") }
                if busy { HStack { ProgressView(); Text("Adding…").foregroundStyle(.secondary) } }
            } header: {
                Text("Send")
            } footer: {
                Text("Anything here reaches your laptop, the G14 and your other \(Device.isPhone ? "iPad" : "iPhone") through the hub. This \(Device.name) sends and takes in files while Nexus is open.")
            }
            Section {
                if items.isEmpty {
                    Text("Nothing here yet. What you send from the laptop shows up here.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("drop-empty")
                }
                ForEach(items) { i in
                    Button { open(i) } label: { DropRowView(row: i, isNew: fresh.contains(i.rel) || i.isNew) }
                        .buttonStyle(.plain)
                        .contextMenu { menu(i) }
                        .swipeActions(edge: .trailing) { Button(role: .destructive) { deleting = i } label: { Label("Delete", systemImage: "trash") } }
                        .accessibilityIdentifier("drop-item-\(i.name)")
                }
            } header: {
                Text(items.isEmpty ? "In Drop" : "In Drop · \(items.count)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Drop")
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { clearing = true } label: { Label("Clear all", systemImage: "trash") }
                        .accessibilityIdentifier("drop-clear")
                }
            }
        }
        .task(id: "\(sync.dropVersion)|\(store.snapshot.loadedAt.timeIntervalSince1970)") { reload() }
        .onAppear {
            fresh = Set(DropRow.list(store.folder).filter(\.isNew).map(\.rel))
            DropCount.markSeen()
        }
        .onChange(of: sync.dropVersion) { _, _ in
            // something came while the screen is open: it is seen here (marked New, no count in the sidebar)
            fresh.formUnion(DropRow.list(store.folder).filter(\.isNew).map(\.rel))
            DropCount.markSeen()
        }
        .refreshable { sync.syncNow(); reload() }
        .quickLookPreview($preview)
        .photosPicker(isPresented: $pickingPhotos, selection: $photos, matching: .any(of: [.images, .videos]), photoLibrary: .shared())
        .onChange(of: photos) { _, picked in
            guard !picked.isEmpty else { return }
            photos = []
            Task { await addPhotos(picked) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { add(urls, scoped: true) }
        }
        .sheet(isPresented: $snapping) {
            SnapCamera { img in
                snapping = false
                guard let img else { return }
                Task { await addSnap(img) }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(deleting.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let i = deleting { remove([i]) } }
        } message: {
            Text("It goes to the bin in this \(Device.name)'s Nexus folder (.trash), and away from your other devices when they sync.")
        }
        .confirmationDialog("Clear Drop?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Delete all \(items.count)", role: .destructive) { remove(items) }
        } message: {
            Text("Everything in Drop goes to the bin in this \(Device.name)'s Nexus folder (.trash), and away from your other devices when they sync.")
        }
    }

    @ViewBuilder
    private func menu(_ i: DropRow) -> some View {
        if !i.isFolder || i.isBoard { Button { open(i) } label: { Label("Open", systemImage: "arrow.up.forward.square") } }
        if !i.isFolder { ShareLink(item: i.url) { Label("Share…", systemImage: "square.and.arrow.up") } }
        Button(role: .destructive) { deleting = i } label: { Label("Delete…", systemImage: "trash") }
    }

    // MARK: doing things

    private func reload() { items = DropRow.list(store.folder) }

    private func open(_ i: DropRow) {
        if i.isBoard { store.openBoard = .init(path: i.rel, focus: nil); return }
        if i.isFolder { store.toast = .init(message: "Folders in Drop open in the Files app or in Files here"); return }
        preview = i.url
    }

    /// Files into Drop (a free name when one is taken), then a sync soon.
    private func add(_ urls: [URL], scoped: Bool, rename: [URL: String] = [:]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dropURL, withIntermediateDirectories: true)
        var touched: [String] = []
        var used = Set(((try? fm.contentsOfDirectory(atPath: dropURL.path)) ?? []).map { $0.lowercased() })
        for u in urls {
            let access = scoped && u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let want = rename[u] ?? u.lastPathComponent
            let ext = (want as NSString).pathExtension
            let stem = (want as NSString).deletingPathExtension
            var name = want
            var n = 2
            while used.contains(name.lowercased()) { name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"; n += 1 }
            let rel = DropFolder.folder + "/" + name
            guard SyncPaths.isSafe(rel), !SyncPaths.isIgnored(rel) else {
                store.problem = "“\(name)” can't be a file name on every device (no \\ : * ? \" < > |, nor a dot or space at the end). Rename it first."
                continue
            }
            used.insert(name.lowercased())
            do {
                try fm.copyItem(at: u, to: dropURL.appendingPathComponent(name))
                touched.append(rel)
            } catch { store.problem = "Couldn't add “\(want)”: \(error.localizedDescription)" }
        }
        guard !touched.isEmpty else { return }
        store.didWrite(listChanged: true, touched: touched)
        sync.wake(touched: touched)
        let first = (touched[0] as NSString).lastPathComponent
        store.toast = .init(message: touched.count == 1 ? "Sending “\(first)” to your other devices" : "Sending \(touched.count) files to your other devices")
        reload()
    }

    /// Photos and videos from the library, as files (a HEIC photo goes as a JPEG, which every device opens).
    private func addPhotos(_ picked: [PhotosPickerItem]) async {
        busy = true
        defer { busy = false }
        var urls: [URL] = []
        var names: [URL: String] = [:]
        for p in picked {
            guard let f = try? await p.loadTransferable(type: PickedFile.self) else { continue }
            let ready = await Task.detached { PickedFile.compatible(f.url) }.value
            urls.append(ready.url)
            names[ready.url] = ready.name
        }
        add(urls, scoped: false, rename: names)
        for u in urls { try? FileManager.default.removeItem(at: u) }
    }

    private func addSnap(_ img: UIImage) async {
        busy = true
        defer { busy = false }
        let name = "Photo \(DropRow.stampName()).jpg"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        let data = await Task.detached { img.jpegData(compressionQuality: 0.88) }.value
        guard let data, (try? data.write(to: tmp)) != nil else { store.problem = "Couldn't save the photo."; return }
        add([tmp], scoped: false, rename: [tmp: name])
        try? FileManager.default.removeItem(at: tmp)
    }

    /// To the bin, as Files does.
    private func remove(_ rows: [DropRow]) {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        var touched: [String] = []
        for i in rows {
            let bin = store.folder.appendingPathComponent(".trash/\(stamp)", isDirectory: true).appendingPathComponent(i.rel)
            do {
                try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: i.url, to: bin)
                touched.append(i.rel)
            } catch { store.problem = "Couldn't delete “\(i.name)”: \(error.localizedDescription)" }
        }
        guard !touched.isEmpty else { return }
        store.didWrite(listChanged: true, touched: touched)
        sync.wake(touched: touched)
        store.toast = .init(message: touched.count == 1 ? "Moved “\((touched[0] as NSString).lastPathComponent)” to the bin" : "Moved \(touched.count) files to the bin")
        reload()
    }
}

/// A photo or video handed over by the Photos picker, as a file of its own in the temp folder.
struct PickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in try PickedFile(copy: received.file) }
        FileRepresentation(importedContentType: .image) { received in try PickedFile(copy: received.file) }
    }

    init(url: URL) { self.url = url }
    init(copy from: URL) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drop-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let to = dir.appendingPathComponent(from.lastPathComponent)
        try FileManager.default.copyItem(at: from, to: to)
        url = to
    }

    /// A HEIC photo as a JPEG beside it (Windows opens a JPEG); anything else as it is. -> the file and the name to give it.
    static func compatible(_ u: URL) -> (url: URL, name: String) {
        let ext = u.pathExtension.lowercased()
        guard ext == "heic" || ext == "heif",
              let src = CGImageSourceCreateWithURL(u as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return (u, u.lastPathComponent) }
        let out = u.deletingPathExtension().appendingPathExtension("jpg")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return (u, u.lastPathComponent) }
        // the photo's own metadata (its orientation, when it was taken) goes with it
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
        var opts = (props as? [CFString: Any]) ?? [:]
        opts[kCGImageDestinationLossyCompressionQuality] = 0.9
        CGImageDestinationAddImage(dest, cg, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return (u, u.lastPathComponent) }
        try? FileManager.default.removeItem(at: u)
        return (out, out.lastPathComponent)
    }
}

/// One file or folder in Drop, with where it came from (this device's record).
struct DropRow: Identifiable, Equatable {
    let entry: FileEntry
    let record: DropItem?
    /// When it came or went (the record's time, else the file's).
    let at: Date
    let isNew: Bool

    var id: String { entry.rel }
    var rel: String { entry.rel }
    var url: URL { entry.url }
    var name: String { entry.name }
    var isFolder: Bool { entry.isFolder }
    var isBoard: Bool { entry.isBoard }
    var isImage: Bool { ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"].contains(entry.ext) }

    /// "From Duo", "Sent from here", or "In Drop" (put there by hand, no record).
    var who: String {
        guard let r = record else { return "In Drop" }
        if r.here { return "Sent from here" }
        return r.from.isEmpty ? "From another device" : "From \(r.from)"
    }

    /// Drop's entries, newest first.
    static func list(_ folder: URL) -> [DropRow] {
        let dir = folder.appendingPathComponent(DropFolder.folder, isDirectory: true)
        let log = DropLog.read(folder)
        let seen = DropCount.seen
        return FileEntry.list(dir, rel: DropFolder.folder, showHidden: false).map { e in
            let r = log.record(for: e.rel)
            let at = r.flatMap { DropFolder.date($0.at) } ?? e.modified ?? .distantPast
            let new = r.map { !$0.here && !$0.from.isEmpty } == true && at > seen
            return DropRow(entry: e, record: r, at: at, isNew: new)
        }
        .sorted { ($0.at, $1.name) > ($1.at, $0.name) }
    }

    /// "2026-11-22 1904", for a photo taken here
    static func stampName(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return String(format: "%04d-%02d-%02d %02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

/// A row: a picture's thumbnail or the file's symbol, its name, who sent it and when, its size.
private struct DropRowView: View {
    let row: DropRow
    let isNew: Bool
    @State private var thumb: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Image(systemName: row.entry.symbol).font(.nx(.title3)).foregroundStyle(row.entry.tint)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.entry.display).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("drop-who")
            }
            Spacer(minLength: 6)
            if isNew {
                Text("New").font(.nx(.caption, .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule()).foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("drop-new")
            }
        }
        .contentShape(Rectangle())
        .task(id: row.url) {
            guard row.isImage else { return }
            let u = row.url
            thumb = await Task.detached { DropRowView.thumbnail(u) }.value
        }
    }

    private var subtitle: String {
        var parts = [row.who, DropRowView.ago(row.at)]
        if let s = row.entry.size { parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return "just now" }
        if m < 60 { return "\(m) min ago" }
        if Calendar.current.isDateInToday(d) { return "today " + d.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(d) { return "yesterday " + d.formatted(date: .omitted, time: .shortened) }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    static func thumbnail(_ u: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 160]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The sidebar's count: files from other devices since Drop was last looked at. Plain numbers in its cache key (ci-lessons, Nov 21).
enum DropCount {
    private static let key = "dropSeen"
    static var seen: Date { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: key)) }
    static func markSeen() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key); cache = nil }

    private struct Key: Equatable { let folder: String; let loaded: Double; let version: Int; let seen: Double }
    private static var cache: (key: Key, n: Int)?

    static func new(_ store: NexusStore, version: Int) -> Int? {
        let k = Key(folder: store.folder.path, loaded: store.snapshot.loadedAt.timeIntervalSince1970, version: version,
                    seen: UserDefaults.standard.double(forKey: key))
        if let c = cache, c.key == k { return c.n == 0 ? nil : c.n }
        let n = DropRow.list(store.folder).filter(\.isNew).count
        cache = (k, n)
        return n == 0 ? nil : n
    }
}
