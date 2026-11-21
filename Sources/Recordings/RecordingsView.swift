import AVFoundation
import AVKit
import SwiftUI
import NexusCore

/// The Recordings screen: start one, and every recording by state (recording, being worked on, ready to review, filed).
struct RecordingsView: View {
    @Environment(NexusStore.self) private var store
    @State private var rec = RecordingService.shared

    var body: some View {
        let _ = rec.version
        let all = Recordings.list(store.folder)
        List {
            Section {
                RecordButtons(big: false)
            } footer: {
                Text("The sound is turned into words on this \(Device.name), then Claude prepares a summary, tasks and dates for you to review. Nothing is filed until you accept it.")
            }
            let review = all.filter { $0.status == .review }
            if !review.isEmpty {
                Section("Ready to review") { ForEach(review) { row($0) } }
            }
            let busy = all.filter { [.recording, .transcribing, .preparing, .failed].contains($0.status) }
            if !busy.isEmpty {
                Section("In progress") { ForEach(busy) { row($0) } }
            }
            let filed = all.filter { $0.status == .filed }
            if !filed.isEmpty {
                Section("Filed") { ForEach(filed) { row($0) } }
            }
            if all.isEmpty {
                Section { Text("No recordings yet.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Recordings")
        .task { RecordingDemo.seed(store); rec.resume(); rec.changed() }
    }

    private func row(_ e: Recordings.Entry) -> some View {
        NavigationLink {
            RecordingPage(path: e.path)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: e.meta.video != nil ? "video" : e.meta.kind.icon)
                    .foregroundStyle(e.status == .review ? Theme.accent : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.meta.title).font(.body.weight(e.status == .review ? .semibold : .regular)).lineLimit(1)
                    Text(subtitle(e)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let w = rec.working[e.path] {
                    ProgressView().controlSize(.small).accessibilityLabel(w)
                } else if e.status == .review {
                    Text("Review").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.15), in: Capsule()).foregroundStyle(Theme.accent)
                }
            }
        }
        .accessibilityIdentifier("rec-row-\(e.meta.title)")
    }

    private func subtitle(_ e: Recordings.Entry) -> String {
        var parts: [String] = []
        if let d = e.meta.startedDate { parts.append(d.formatted(date: .abbreviated, time: .shortened)) }
        parts.append(Recordings.clock(e.meta.duration))
        if let s = e.meta.subject, let w = store.workstream(s) { parts.append(w.name) }
        parts.append(rec.working[e.path] ?? e.status.label)
        return parts.joined(separator: " · ")
    }
}

/// The three ways to start: a meeting, a class (sound), a class on film. While one runs, its time and Stop.
struct RecordButtons: View {
    var big: Bool
    @State private var rec = RecordingService.shared

    struct Item: Identifiable { let id: String; let label: String; let icon: String; let kind: Recordings.Kind; let film: Bool }
    static let items = [
        Item(id: "rec-start-meeting", label: "Meeting", icon: "mic.fill", kind: .meeting, film: false),
        Item(id: "rec-start-class", label: "Class", icon: "graduationcap.fill", kind: .lesson, film: false),
        Item(id: "rec-start-film", label: "Film a class", icon: "video.fill", kind: .lesson, film: true),
    ]

    var body: some View {
        if let a = rec.active {
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text("\(a.meta.kind.word) · \(Recordings.clock(rec.elapsed))").monospacedDigit().font(big ? .title3.weight(.semibold) : .body.weight(.semibold))
                Spacer()
                Button { rec.snap() } label: { Label("Snap", systemImage: "camera") }.buttonStyle(.bordered)
                Button(role: .destructive) { Task { await rec.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .accessibilityIdentifier("rec-stop")
            }
            .padding(.vertical, big ? 8 : 2)
        } else {
            HStack(spacing: 10) {
                ForEach(Self.items) { it in
                    Button { Task { await rec.start(it.kind, film: it.film) } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: it.icon).font(big ? .title : .title3)
                            Text(it.label).font(big ? .headline : .subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: big ? 96 : 64)
                    }
                    .buttonStyle(.bordered)
                    .tint(it.kind == .meeting ? .red : Theme.accent)
                    .accessibilityIdentifier(it.id)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// One recording: play it, read it, and review what Claude prepared (or see what was filed).
struct RecordingPage: View {
    let path: String
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var calendar
    @State private var rec = RecordingService.shared
    @State private var meta: Recordings.Meta?
    @State private var transcript: Recordings.Transcript?
    @State private var proposal: Recordings.Proposal?
    @State private var filed: Recordings.Filed?
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var dateSheet: Recordings.ProposedDate?
    @State private var bigPicture: Recordings.Picture?

    private var folder: URL { store.folder.appendingPathComponent(path) }

    var body: some View {
        List {
            if let m = meta {
                header(m)
                if let w = rec.working[path] {
                    Section { HStack(spacing: 10) { ProgressView(); Text(w) } }
                } else if let why = rec.problems[path] ?? (m.state == "failed" ? m.problem : nil) {
                    Section {
                        Text(why).foregroundStyle(Theme.late)
                        Button("Try again") { Task { await rec.process(path); load() } }
                    }
                }
                if filed == nil, proposal != nil { review }
                if let f = filed, let p = proposal { filedSection(p, f) }
                if !m.pictures.isEmpty { picturesSection(m) }
                if let t = transcript { transcriptSection(t) }
            } else {
                Text("This recording can't be read.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(meta?.title ?? "Recording")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: rec.version) { _, _ in load() }
        .onDisappear { player?.pause() }
        .sheet(item: Binding(get: { dateSheet.map { DateItem(d: $0) } }, set: { dateSheet = $0?.d })) { item in
            HeardDateSheet(store: calendar.ek, date: item.d) { dateSheet = nil; calendar.reloadCalendars() }.ignoresSafeArea()
        }
        .sheet(item: Binding(get: { bigPicture.map { PicItem(p: $0) } }, set: { bigPicture = $0?.p })) { item in
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    if let img = UIImage(contentsOfFile: folder.appendingPathComponent(item.p.file).path) { Image(uiImage: img).resizable().scaledToFit() }
                }
                .navigationTitle(Recordings.clock(item.p.at))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { bigPicture = nil } }
                    ToolbarItem(placement: .bottomBar) { Button("Play from here") { bigPicture = nil; seek(item.p.at) } }
                }
            }
        }
    }

    struct DateItem: Identifiable { let d: Recordings.ProposedDate; var id: String { d.what + d.date } }
    struct PicItem: Identifiable { let p: Recordings.Picture; var id: String { p.file } }

    // MARK: parts

    @ViewBuilder
    private func header(_ m: Recordings.Meta) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(m.kind.word + (m.video != nil ? " (filmed)" : ""), systemImage: m.video != nil ? "video" : m.kind.icon)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(m.title).font(.title2.weight(.semibold))
                Text([m.startedDate.map { $0.formatted(date: .complete, time: .shortened) }, Recordings.clock(m.duration), m.device].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let v = m.video, FileManager.default.fileExists(atPath: folder.appendingPathComponent(v).path), let player {
                VideoPlayer(player: player).frame(height: 220).listRowInsets(EdgeInsets())
            } else if player != nil {
                HStack {
                    Button { toggle() } label: { Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle) }
                        .buttonStyle(.plain).accessibilityLabel(playing ? "Pause" : "Play")
                    Text(playing ? "Playing" : "Play the recording").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subjectBinding: Binding<String> {
        Binding(get: { proposal?.subject ?? "" }, set: { proposal?.subject = $0.isEmpty ? nil : $0 })
    }

    private var subjects: [Workstream] {
        store.snapshot.workstreams.values.filter { !$0.parked && !$0.finished }.sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var review: some View {
        if let p = proposal {
            Section {
                TextField("Title", text: Binding(get: { proposal?.title ?? "" }, set: { proposal?.title = $0 }))
                    .font(.headline)
                Picker("Files under", selection: subjectBinding) {
                    Text("Inbox").tag("")
                    ForEach(subjects) { w in Text(w.name).tag(w.id) }
                }
                .accessibilityIdentifier("rec-subject")
            } header: {
                Label("Claude prepared this. Check it, then accept.", systemImage: "sparkles").foregroundStyle(Theme.claude).textCase(nil)
            }
            Section("Summary") {
                Text(LocalizedStringKey(p.summary)).fixedSize(horizontal: false, vertical: true)
                if !p.people.isEmpty { Text("With " + p.people.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary) }
                ForEach(p.decisions, id: \.self) { d in Label(d, systemImage: "checkmark.seal") }
            }
            if !p.tasks.isEmpty {
                Section {
                    ForEach(p.tasks.indices, id: \.self) { i in
                        Toggle(isOn: Binding(get: { proposal?.tasks[i].take ?? false }, set: { proposal?.tasks[i].take = $0 })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.tasks[i].title)
                                Text([p.tasks[i].due.map { "Due " + Days.label($0) }, p.tasks[i].at.map { "said at " + Recordings.clock($0) }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Tasks to add to \(store.workstream(p.subject)?.name ?? "the Inbox")") }
            }
            if !p.dates.isEmpty { datesSection(p.dates) }
            if let c = p.classNotes { classSection(c, teachingToggle: true) }
            Section {
                Button { accept() } label: {
                    Label("Accept and file", systemImage: "tray.and.arrow.down.fill").frame(maxWidth: .infinity).font(.headline)
                }
                .buttonStyle(.borderedProminent).listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .accessibilityIdentifier("rec-accept")
                Button("Ask Claude again") {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(Recordings.proposalFile))
                    proposal = nil
                    Task { await rec.process(path); load() }
                }
            } footer: {
                Text("Accepting writes the summary beside the recording, adds the ticked tasks" + (p.classNotes != nil ? " and the teaching notes" : "") + ". Undo on the bar takes it back.")
            }
        }
    }

    @ViewBuilder
    private func filedSection(_ p: Recordings.Proposal, _ f: Recordings.Filed) -> some View {
        Section {
            Label("Filed under \(store.workstream(f.subject)?.name ?? "the Inbox")", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            Text(LocalizedStringKey(p.summary)).fixedSize(horizontal: false, vertical: true)
            ForEach(p.decisions, id: \.self) { d in Label(d, systemImage: "checkmark.seal") }
        } header: { Text("Summary") }
        if !f.tasks.isEmpty {
            Section("Tasks added") {
                ForEach(f.tasks.map { $0.id }, id: \.self) { id in
                    if let task = store.task(id) {
                        TaskRow(task: task, showWorkstream: true, compact: true)
                    }
                }
            }
        }
        if !p.dates.isEmpty { datesSection(p.dates) }
        if let c = p.classNotes { classSection(c, teachingToggle: false) }
    }

    private func datesSection(_ dates: [Recordings.ProposedDate]) -> some View {
        Section {
            ForEach(dates, id: \.what) { d in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.what)
                        Text(Days.label(d.date) + (d.time.map { ", \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if calendar.canRead {
                        Button("Add to calendar") { dateSheet = d }.buttonStyle(.bordered).font(.caption)
                    }
                }
            }
        } header: { Text("Dates heard") } footer: { Text("Nothing goes into your calendar unless you add it here.") }
    }

    @ViewBuilder
    private func classSection(_ c: Recordings.ClassNotes, teachingToggle: Bool) -> some View {
        Section("What was taught" + (c.unit.map { " · \($0)" } ?? "")) {
            Text(LocalizedStringKey(c.taught)).fixedSize(horizontal: false, vertical: true)
            ForEach(c.examples, id: \.self) { e in Label(e, systemImage: "pencil.and.list.clipboard") }
        }
        if !c.teaching.isEmpty {
            Section {
                Text(LocalizedStringKey(c.teaching)).fixedSize(horizontal: false, vertical: true)
                if teachingToggle, let w = store.workstream(proposal?.subject) {
                    Toggle("Add to \(w.name)'s teaching notes", isOn: Binding(get: { proposal?.takeTeaching ?? true }, set: { proposal?.takeTeaching = $0 }))
                }
            } header: { Text("How it was taught") } footer: { Text("The tutor reads these to explain things the way your class does.") }
        }
    }

    private func picturesSection(_ m: Recordings.Meta) -> some View {
        Section("Pictures") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(m.pictures, id: \.file) { p in
                        Button { bigPicture = p } label: {
                            VStack(spacing: 4) {
                                if let img = UIImage(contentsOfFile: folder.appendingPathComponent(p.file).path) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 150, height: 100).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(width: 150, height: 100)
                                }
                                Text(Recordings.clock(p.at) + (p.note.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func transcriptSection(_ t: Recordings.Transcript) -> some View {
        Section {
            ForEach(Array(t.paragraphs().enumerated()), id: \.offset) { _, p in
                Button { seek(p.start) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Recordings.clock(p.start)).font(.caption.monospacedDigit()).foregroundStyle(Theme.accent).frame(minWidth: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            if let s = p.speaker { Text(proposal?.speakers[s] ?? s).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                            Text(p.text).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: { Text("Transcript") } footer: { Text("\(t.words) words. Tap a line to play from there.") }
    }

    // MARK: actions

    private func load() {
        meta = rec.readMeta(path)
        func json(_ f: String) -> JSONValue? { (try? FolderAccess.read(folder.appendingPathComponent(f))).flatMap { try? JSONValue.parse($0) } }
        transcript = json(Recordings.transcriptFile).flatMap { Recordings.Transcript(json: $0) }
        filed = json(Recordings.filedFile).flatMap { Recordings.Filed(json: $0) }
        // a proposal being edited stays as edited until it is accepted
        if proposal == nil || filed != nil { proposal = json(Recordings.proposalFile).flatMap { Recordings.Proposal(json: $0) } }
        if player == nil, let m = meta {
            let media = folder.appendingPathComponent(m.video ?? m.audio)
            let url = FileManager.default.fileExists(atPath: media.path) ? media : folder.appendingPathComponent(m.audio)
            if FileManager.default.fileExists(atPath: url.path) { player = AVPlayer(url: url) }
        }
    }

    private func toggle() {
        guard let player else { return }
        if playing { player.pause() } else { try? AVAudioSession.sharedInstance().setCategory(.playback); player.play() }
        playing.toggle()
    }

    private func seek(_ at: Double) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: at, preferredTimescale: 600))
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player.play()
        playing = true
    }

    private func accept() {
        guard let p = proposal else { return }
        RecordingFiler.accept(path: path, proposal: p, store: store)
        load()
    }
}

/// While recording, on every screen: a red pill with the time, Snap and Stop; filming shows the camera full screen instead.
struct RecordingTopBar: ViewModifier {
    @State private var rec = RecordingService.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let a = rec.active, !a.filming {
                    HStack(spacing: 10) {
                        Circle().fill(.red).frame(width: 9, height: 9)
                        Text("Recording \(a.meta.kind.word.lowercased()) · \(Recordings.clock(rec.elapsed))").font(.subheadline.weight(.semibold)).monospacedDigit()
                        Spacer()
                        Button { rec.snap() } label: { Image(systemName: "camera.fill") }.accessibilityLabel("Snap a picture")
                        Button { Task { await rec.stop() } } label: { Image(systemName: "stop.fill").foregroundStyle(.red) }
                            .accessibilityLabel("Stop recording").accessibilityIdentifier("rec-bar-stop")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.12))
                    .accessibilityIdentifier("rec-bar")
                }
            }
            .sheet(isPresented: Binding(get: { rec.snapping }, set: { rec.snapping = $0 })) {
                SnapCamera { img in
                    rec.snapping = false
                    if let img { rec.addPicture(img) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: Binding(get: { rec.active?.filming == true }, set: { _ in })) {
                ZStack(alignment: .bottom) {
                    if RecordingDemo.on {
                        Color.black.overlay(Text("Camera").foregroundStyle(.white.opacity(0.5)))
                    } else {
                        FilmPreview(session: rec.camera.session)
                    }
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 10, height: 10)
                            Text("Filming · \(Recordings.clock(rec.elapsed))").monospacedDigit().font(.headline)
                            if let n = rec.active?.marks.count, n > 0 { Text("· \(n) snapped").font(.subheadline) }
                        }
                        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.5), in: Capsule())
                        HStack(spacing: 40) {
                            Button { rec.snap() } label: { Label("Snap this", systemImage: "camera.viewfinder").font(.headline) }
                                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                            Button { Task { await rec.stop() } } label: { Label("Stop", systemImage: "stop.fill").font(.headline) }
                                .buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("rec-film-stop")
                        }
                        Text("Keep Nexus open while filming: the camera stops when the screen locks.").font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.bottom, 30)
                }
                .ignoresSafeArea()
            }
            .alert("Recording", isPresented: Binding(get: { rec.problem != nil }, set: { if !$0 { rec.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(rec.problem ?? "") }
    }
}

extension View {
    func recordingBar() -> some View { modifier(RecordingTopBar()) }
}

/// How many recordings wait for review (the sidebar's number), read again only when the folder or a recording changed.
@MainActor
enum RecordingsCount {
    private static var cache: (key: String, n: Int)?

    static func review(_ store: NexusStore) -> Int? {
        let key = "\(store.folder.path)|\(store.snapshot.loadedAt)|\(RecordingService.shared.version)"
        if let c = cache, c.key == key { return c.n == 0 ? nil : c.n }
        let n = Recordings.list(store.folder).filter { $0.status == .review }.count
        cache = (key, n)
        return n == 0 ? nil : n
    }
}
