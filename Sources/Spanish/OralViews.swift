import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NexusCore

/// Spanish › Oral on the iPhone and iPad (the laptop's Study › Oral practice, desktop/src/screens/study/Oral.tsx): the past orals with
/// their marks over time, one oral (the marks given and Claude's, what the ears heard, the picture, notes, what was said), Add a
/// recording (recorded here or chosen from Files) and the listening test. The practice oral with the examiner's voice, the picture
/// bank, the questions and the marking run on the laptop; what the phone adds waits there to be heard (OralLibrary).
struct OralPage: View {
    let workstreamId: String
    @Environment(NexusStore.self) private var store
    @State private var by = "all"
    @State private var adding = false
    var lib: OralLibrary { .shared }

    var body: some View {
        Group {
            if let w = store.workstream(workstreamId) {
                list(w)
            } else {
                EmptyNote(title: "This workstream is gone", icon: "questionmark.folder")
            }
        }
        .navigationTitle("Oral practice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("Add a recording", systemImage: "plus") }
                    .disabled(!lib.canWrite(store))
                    .accessibilityIdentifier("oral-add")
            }
        }
        .sheet(isPresented: $adding) { OralAddSheet(workstreamId: workstreamId) }
        .alert("Oral practice", isPresented: Binding(get: { lib.problem != nil }, set: { if !$0 { lib.problem = nil } })) {
            Button("OK") { lib.problem = nil }
        } message: { Text(lib.problem ?? "") }
        .task(id: store.snapshot.loadedAt) { if let w = store.workstream(workstreamId) { lib.refreshIfChanged(store, w) } }
    }

    private func list(_ w: Workstream) -> some View {
        let h = lib.home(w.id)
        let shown = h.rows.filter { by == "all" || $0.by == by }
        let pts = Array(h.rows.filter { $0.share != nil }.prefix(20).reversed())
        return List {
            Section {
                Button { adding = true } label: {
                    OralGo(icon: "mic", title: "Add a recording", detail: "A session with \(h.settings.tutor), or an oral \(h.settings.teacher) marked: record it here or choose a file")
                }
                .disabled(!lib.canWrite(store))
                .accessibilityIdentifier("oral-add-row")
                NavigationLink { OralListeningTest(workstreamId: w.id) } label: {
                    OralGo(icon: "ear", title: "Listening test", detail: "Read nine lines so the laptop can show how well its ears hear your voice")
                }
                .accessibilityIdentifier("oral-test-row")
            } footer: {
                Text("Practice orals with the examiner's voice, the pictures and Claude's marking are on the laptop's Oral page.")
            }
            if h.waiting > 0 {
                Section {
                    Label {
                        Text("\(h.waiting) \(h.waiting == 1 ? "recording waits" : "recordings wait") for the laptop. Its ears write down what was said and listen to how you said it the next time its Oral page is open.")
                            .font(.nx(.callout))
                    } icon: { Image(systemName: "laptopcomputer").foregroundStyle(Theme.soon) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("oral-waiting")
                }
            }
            Section {
                Picker("Show", selection: $by) {
                    Text("All \(h.rows.count)").tag("all")
                    ForEach(["practice", "teacher", "tutor"], id: \.self) { k in
                        Text("\(SpanishOral.who(k, settings: h.settings)) \(h.rows.filter { $0.by == k }.count)").tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("oral-filter")
                if pts.count >= 2 { OralTrend(points: pts, settings: h.settings).accessibilityIdentifier("oral-trend") }
                if shown.isEmpty {
                    Text(h.rows.isEmpty ? "No orals yet." : "None of these yet.").foregroundStyle(.secondary)
                }
                ForEach(shown) { r in
                    NavigationLink { OralDetail(workstreamId: w.id, oralId: r.id) } label: { OralRowView(row: r, workstream: w, settings: h.settings) }
                        .accessibilityIdentifier("oral-row")
                }
            } header: {
                Text("Orals").textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct OralGo: View {
    var icon, title, detail: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.nx(.body, .medium)).foregroundStyle(Color.primary)
                Text(detail).font(.nx(.caption)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Who an oral is by, as a chip: the teacher amber, the tutor Claude's blue, practice green.
struct OralByChip: View {
    var by: String
    var settings: SpanishOral.Settings
    static func color(_ by: String) -> Color { by == "teacher" ? Theme.soon : by == "tutor" ? Theme.claude : Theme.accent }
    var body: some View {
        Text(SpanishOral.who(by, settings: settings))
            .font(.nx(.caption, .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(Self.color(by))
            .background(Self.color(by).opacity(0.13), in: RoundedRectangle(cornerRadius: Kit.chipRadius))
    }
}

/// The marks over time: a bar an oral, its height the share of the marks, coloured by who marked it.
private struct OralTrend: View {
    var points: [SpanishOral.Row]
    var settings: SpanishOral.Settings
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(points) { p in
                RoundedRectangle(cornerRadius: 2)
                    .fill(OralByChip.color(p.by))
                    .frame(maxWidth: 18)
                    .frame(height: max(4, (p.share ?? 0) * 60))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 64, alignment: .bottom)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Marks over time: " + points.map { "\(SpanishOral.who($0.by, settings: settings)) \(OralRowView.mark($0.total))/\(OralRowView.mark($0.max))" }.joined(separator: ", "))
    }
}

struct OralRowView: View {
    var row: SpanishOral.Row
    var workstream: Workstream
    var settings: SpanishOral.Settings
    @Environment(NexusStore.self) private var store

    static func mark(_ d: Double?) -> String { d.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) } ?? "?" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OralPicture(url: row.image.isEmpty ? nil : OralLibrary.shared.url(store, workstream, "images/" + row.image))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.nx(.body, .medium)).lineLimit(2)
                Text(row.when + (row.from.isEmpty ? "" : " · from the \(row.from)")).font(.nx(.caption)).foregroundStyle(.secondary)
                if !row.summary.isEmpty { Text(row.summary).font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                OralByChip(by: row.by, settings: settings)
                if row.waiting == "hear" {
                    Text("Waiting for the laptop").font(.nx(.caption2)).foregroundStyle(Theme.soon)
                } else if let t = row.total {
                    Text("\(Self.mark(t))/\(Self.mark(row.max))").font(.nx(.callout, .semibold)).monospacedDigit()
                } else if row.by == "practice" {
                    Text("not marked").font(.nx(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A picture from the bank, or a quiet square.
struct OralPicture: View {
    var url: URL?
    var body: some View {
        if let url, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Kit.rests)
                .overlay(Image(systemName: "waveform").foregroundStyle(.tertiary))
        }
    }
}

// MARK: one oral

struct OralDetail: View {
    let workstreamId: String
    let oralId: String
    @Environment(NexusStore.self) private var store
    @State private var player = OralPlayer()
    @State private var problem: String?
    var lib: OralLibrary { .shared }

    var body: some View {
        let h = lib.home(workstreamId)
        Group {
            if let o = h.oral(oralId), let w = store.workstream(workstreamId) {
                ScrollView { content(o, w, h).padding(16).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity) }
                    .background(Color(.systemGroupedBackground))
            } else {
                EmptyNote(title: "This oral is gone", icon: "questionmark.folder")
            }
        }
        .navigationTitle(h.oral(oralId).map { SpanishOral.title($0, settings: h.settings, images: h.images) } ?? "Oral")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
        .alert("Oral practice", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
    }

    @ViewBuilder
    private func content(_ o: SpanishOral.Oral, _ w: Workstream, _ h: OralLibrary.Home) -> some View {
        let who = SpanishOral.who(o.by, settings: h.settings)
        let kind = ["full": "Full oral", "conversation": "Conversation", "session": "Session"][o.kind] ?? o.kind
        let meta = [SpanishOral.when(o.started), kind, o.theme.isEmpty ? "" : SpanishOral.themeName(o.theme), o.otherTheme.isEmpty ? "" : "Part 3: " + SpanishOral.themeName(o.otherTheme)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(SpanishOral.title(o, settings: h.settings, images: h.images)).font(.nx(.title2, .semibold))
                Spacer()
                OralByChip(by: o.by, settings: h.settings)
            }
            Text(meta).font(.nx(.caption)).foregroundStyle(.secondary)
            if o.waiting == "hear" {
                card {
                    Label("Waiting for the laptop", systemImage: "laptopcomputer").font(.nx(.body, .semibold)).foregroundStyle(Theme.soon)
                    Text("Added on the \(o.from.isEmpty ? "phone" : o.from). The laptop's ears write down what was said, tell your answers from the questions and feedback, and listen to how you said it the next time its Oral page is open; then Claude can mark it there.")
                        .font(.nx(.callout))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("oral-one-waiting")
            }
            if let g = o.given, g.total != nil || !g.comments.isEmpty || !g.points.isEmpty {
                card {
                    let crit = SpanishOral.critMax.filter { g.crit[$0.key] != nil }.map { "\($0.key) \(OralRowView.mark(g.crit[$0.key]))" }.joined(separator: " · ")
                    Text("\(who): " + (g.total != nil ? "\(OralRowView.mark(g.total))/\(OralRowView.mark(g.max))" : "no marks")).font(.nx(.body, .semibold))
                    if !crit.isEmpty { Text(crit).font(.nx(.caption)).foregroundStyle(.secondary) }
                    if !g.comments.isEmpty { Text(g.comments).font(.nx(.callout)) }
                    ForEach(g.points, id: \.self) { p in Text("• " + p).font(.nx(.callout)) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("oral-given")
            }
            if let t = o.marks?["total"] {
                card {
                    let crit = SpanishOral.critMax.filter { o.kind != "conversation" || $0.key != "B1" }.map { "\($0.key) \(o.marks?[$0.key].map { OralRowView.mark($0) } ?? "–")" }.joined(separator: " · ")
                    Text("Claude: \(OralRowView.mark(t))/\(SpanishOral.maxOf(o.kind))").font(.nx(.body, .semibold))
                    Text(crit).font(.nx(.caption)).foregroundStyle(.secondary)
                    if !o.summary.isEmpty { Text(o.summary).font(.nx(.callout)) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("oral-claude")
            }
            if let heard = SpanishOral.heard(o.listening) { listening(heard) }
            if let p = h.images.first(where: { $0.file == o.image }) {
                card {
                    OralPicture(url: lib.url(store, w, "images/" + p.file)).frame(maxWidth: .infinity).frame(height: 220).clipped()
                    Text(SpanishOral.labelFor(p)).font(.nx(.callout))
                }
            }
            if !o.notes.isEmpty {
                section("Your notes")
                card { Text(o.notes).font(.system(.callout, design: .monospaced)) }
            }
            if !o.recording.isEmpty {
                let u = lib.url(store, w, "orals/\(o.id)/\(o.recording)")
                if FileManager.default.fileExists(atPath: u.path) {
                    Button { problem = player.toggle(u) } label: {
                        Label(player.playing ? "Pause the recording" : "Play the recording", systemImage: player.playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("oral-play")
                } else {
                    Text("Recording: \(o.recording) (on the laptop)").font(.nx(.caption)).foregroundStyle(.secondary)
                }
            }
            if !o.segments.isEmpty {
                section("What you said")
                ForEach(Array(o.segments.enumerated()), id: \.offset) { _, s in
                    card {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Part \(s.part)").font(.nx(.callout, .semibold))
                            if !s.q.isEmpty { Text(s.q).font(.nx(.callout)).foregroundStyle(.secondary) }
                            Spacer()
                            Text("\(Int((s.ms / 1000).rounded())) s").font(.nx(.caption)).foregroundStyle(.secondary)
                        }
                        Text(s.heard.isEmpty ? "(nothing heard)" : s.heard).font(.nx(.callout))
                        if !s.said.isEmpty && s.said != s.heard { Text("As said: " + s.said).font(.nx(.caption)).foregroundStyle(.secondary) }
                    }
                }
            }
            if !o.turns.isEmpty {
                section("Who said what")
                card {
                    ForEach(Array(o.turns.enumerated()), id: \.offset) { _, t in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%d:%02d", Int(t.start) / 60, Int(t.start) % 60)).font(.nx(.caption)).foregroundStyle(.secondary).monospacedDigit()
                            Text(t.who == "me" ? "You" : t.who == "feedback" ? "Feedback" : who).font(.nx(.caption, .semibold))
                                .foregroundStyle(t.who == "me" ? Theme.accent : t.who == "feedback" ? Theme.soon : Theme.claude)
                                .frame(width: 70, alignment: .leading)
                            Text(t.text).font(.nx(.callout))
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("oral-turns")
            }
        }
    }

    @ViewBuilder
    private func listening(_ L: SpanishOral.Heard) -> some View {
        card {
            Text("What the listening heard").font(.nx(.body, .semibold))
            if let t = L.talkLine { Text(t).font(.nx(.callout)) }
            if !L.diffs.isEmpty {
                ForEach(Array(L.diffs.prefix(12).enumerated()), id: \.offset) { _, d in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(d.said.isEmpty ? "(nothing)" : d.said).strikethrough().foregroundStyle(Theme.late)
                        Text("→")
                        Text(d.meant.isEmpty ? "(nothing)" : d.meant).bold()
                        Text(d.kind + (d.part.isEmpty ? "" : ", " + d.part)).font(.nx(.caption)).foregroundStyle(.secondary)
                    }
                    .font(.nx(.callout))
                }
            } else if L.saidEar {
                Text("The words as you said them match what you meant.").font(.nx(.caption)).foregroundStyle(.secondary)
            }
            ForEach(L.sounds, id: \.kind) { s in
                (Text(s.say).bold() + Text(": " + (s.count.map { "\($0) × · " } ?? "") + s.words.joined(separator: ", "))).font(.nx(.callout))
            }
            if !L.delivery.isEmpty { Text(L.delivery.joined(separator: " · ")).font(.nx(.caption)).foregroundStyle(.secondary) }
            if !L.saidEar && !L.soundsEar && L.talkLine == nil {
                Text("The words-as-said and sounds ears did not run" + (L.earError.isEmpty ? "." : ": " + L.earError)).font(.nx(.caption)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("oral-listen")
    }

    private func section(_ t: String) -> some View { Text(t).font(.nx(.headline)).padding(.top, 6) }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { c() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Kit.surfaceRadius))
    }
}

// MARK: Add a recording

struct OralAddSheet: View {
    let workstreamId: String
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var r = SpanishOral.NewRecording()
    @State private var day = Date()
    @State private var file: URL?
    @State private var fileNote = ""
    @State private var picking = false
    @State private var mic = OralMic()
    @State private var marks: [String: String] = [:]
    @State private var problem: String?
    @State private var saving = false
    var lib: OralLibrary { .shared }

    var body: some View {
        let s = lib.home(workstreamId).settings
        NavigationStack {
            Form {
                Section {
                    Picker("Who", selection: Binding(get: { r.by }, set: { b in r.by = b; r.kind = b == "tutor" ? "session" : "full"; if b == "teacher", marks["max", default: ""].isEmpty { marks["max"] = "30" } })) {
                        Text("A session with \(s.tutor)").tag("tutor")
                        Text("An oral \(s.teacher) marked").tag("teacher")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("oral-i-by")
                }
                Section {
                    if mic.on {
                        HStack {
                            Image(systemName: "record.circle").foregroundStyle(Theme.late).symbolEffect(.pulse)
                            Text("Recording " + OralMic.time(mic.seconds)).monospacedDigit()
                            Spacer()
                            Button("Stop") { if let u = mic.stop() { file = u; fileNote = "Recorded here, " + OralMic.time(mic.seconds) } }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("oral-i-stop")
                        }
                    } else {
                        Button { Task { if let why = await mic.start() { problem = why } } } label: { Label(file == nil ? "Record it now" : "Record it again", systemImage: "mic") }
                            .accessibilityIdentifier("oral-i-record")
                        Button { picking = true } label: { Label("Choose a file", systemImage: "folder") }
                            .accessibilityIdentifier("oral-i-pick")
                    }
                } header: { Text("The recording").textCase(nil) } footer: {
                    Text(fileNote.isEmpty ? "A voice memo, a WhatsApp audio or video, an .m4a, .mp3 or .wav." : fileNote)
                        .accessibilityIdentifier("oral-i-fname")
                }
                Section {
                    DatePicker("Date", selection: $day, displayedComponents: .date)
                    TextField("Title (optional): \"Summative IO\"", text: $r.title).accessibilityIdentifier("oral-i-title")
                    Picker("Format", selection: $r.kind) {
                        Text("Free practice").tag("session")
                        Text("A full oral").tag("full")
                        Text("Conversation only").tag("conversation")
                    }
                }
                Section {
                    ForEach(0..<SpanishOral.critMax.count, id: \.self) { i in markField("\(SpanishOral.critMax[i].key) /\(SpanishOral.critMax[i].max)", SpanishOral.critMax[i].key) }
                    markField("Total", "total")
                    markField("Out of", "max")
                } header: { Text("Marks, if you have them").textCase(nil) } footer: {
                    Text("By criterion, or only a total out of \(r.by == "tutor" ? "their" : "her") own maximum. Leave out what you don't have; marks said in the recording are picked up on the laptop.")
                }
                Section("Comments") {
                    TextField("Written comments, if any", text: $r.comments, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("oral-i-com")
                }
            }
            .navigationTitle("Add a recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { mic.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add it", action: save).disabled(file == nil || mic.on || saving).accessibilityIdentifier("oral-i-add")
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie]) { res in
                if case .success(let u) = res {
                    file = u
                    let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    fileNote = "\(u.lastPathComponent) (\(max(1, size / 1_000_000)) MB)"
                }
            }
            .alert("Add a recording", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK") { problem = nil }
            } message: { Text(problem ?? "") }
        }
        .interactiveDismissDisabled(mic.on)
    }

    private func markField(_ label: String, _ key: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: Binding(get: { marks[key] ?? "" }, set: { marks[key] = $0 }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityIdentifier("oral-i-\(key)")
        }
    }

    private func save() {
        guard let file, let w = store.workstream(workstreamId) else { return }
        func n(_ k: String) -> Double? { Double((marks[k] ?? "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
        var rec = r
        rec.crit = [:]
        for (k, _) in SpanishOral.critMax { if let v = n(k) { rec.crit[k] = v } }
        rec.total = n("total")
        rec.max = n("max")
        saving = true
        do {
            try lib.add(store, w, rec, audio: file, day: day)
            store.toast = .init(message: "Added. The laptop hears it the next time its Oral page is open.")
            dismiss()
        } catch {
            problem = "It couldn't be added: \(error.localizedDescription)"
        }
        saving = false
    }
}

// MARK: the listening test

struct OralListeningTest: View {
    let workstreamId: String
    @Environment(NexusStore.self) private var store
    @State private var mic = OralMic()
    @State private var recording: String?
    @State private var done: [String: URL] = [:]
    @State private var problem: String?
    var lib: OralLibrary { .shared }

    var body: some View {
        let h = lib.home(workstreamId)
        let lines = SpanishOral.listenTest
        List {
            Section {
                Text("Read each line exactly as written, mistakes included: some have grammar mistakes on purpose, some ask you to say a sound the English way. The laptop's ears hear the take: the words ear should keep each mistake, the sounds ear should flag each English sound, and nothing should be flagged in the last line.")
                    .font(.nx(.footnote)).foregroundStyle(.secondary)
            }
            Section {
                ForEach(lines, id: \.id) { l in line(l) }
            } header: { Text("\(done.count) of \(lines.count) read").textCase(nil) }
            Section {
                Button { send(lines) } label: { Label("Send to the laptop", systemImage: "laptopcomputer.and.arrow.down") }
                    .disabled(done.count < lines.count || mic.on || !lib.canWrite(store))
                    .accessibilityIdentifier("oral-t-send")
            } footer: { Text("Its ears hear the take the next time its Oral page is open, and keep the result there and here.") }
            if !h.takes.isEmpty || !h.tests.isEmpty {
                Section {
                    ForEach(h.takes, id: \.stamp) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read on the \(t.device.isEmpty ? "phone" : t.device) · " + String(t.at.prefix(16)).replacingOccurrences(of: "T", with: " ")).font(.nx(.callout))
                            Text(t.heard.isEmpty ? "Waiting for the laptop" : "Heard").font(.nx(.caption)).foregroundStyle(t.heard.isEmpty ? Theme.soon : .secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("oral-t-take")
                    }
                    ForEach(h.tests, id: \.file) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(r.at.prefix(10)) + (r.from.isEmpty ? "" : " · read on the \(r.from)")).font(.nx(.callout, .medium))
                            Text("Grammar mistakes kept by the words ear: \(r.grammarSaid) of \(r.grammarTotal) (Whisper kept \(r.grammarMeant)) · English sounds flagged: \(r.soundsFlagged) of \(r.soundsTotal) · false flags: \(r.falseFlags)")
                                .font(.nx(.caption)).foregroundStyle(.secondary)
                            if !r.advice.isEmpty { Text(r.advice).font(.nx(.callout)) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("oral-t-result")
                    }
                } header: { Text("Takes and results").textCase(nil) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Listening test")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { mic.cancel(); recording = nil }
        .task(id: store.snapshot.loadedAt) { if let w = store.workstream(workstreamId) { lib.refreshIfChanged(store, w) } }
        .alert("Listening test", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
    }

    private func line(_ l: SpanishOral.Line) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.read).font(.nx(.body, .medium))
            if !l.how.isEmpty { Text(l.how).font(.nx(.caption)).foregroundStyle(.secondary) }
            HStack {
                if recording == l.id {
                    Button { if let u = mic.stop() { done[l.id] = u }; recording = nil } label: { Label("Stop " + OralMic.time(mic.seconds), systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("oral-t-stop")
                } else {
                    Button {
                        Task {
                            if let why = await mic.start() { problem = why } else { recording = l.id }
                        }
                    } label: { Label(done[l.id] == nil ? "Record" : "Again", systemImage: "mic") }
                        .buttonStyle(.bordered)
                        .disabled(mic.on)
                        .accessibilityIdentifier("oral-t-rec-\(l.id)")
                }
                if done[l.id] != nil && recording != l.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityLabel("Read")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func send(_ lines: [SpanishOral.Line]) {
        guard let w = store.workstream(workstreamId) else { return }
        do {
            try lib.saveTake(store, w, lines.compactMap { l in done[l.id].map { (id: l.id, file: $0) } })
            done = [:]
            store.toast = .init(message: "Sent. The laptop hears it the next time its Oral page is open.")
        } catch {
            problem = "It couldn't be saved: \(error.localizedDescription)"
        }
    }
}
