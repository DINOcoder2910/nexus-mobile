import AVFoundation
import EventKit
import EventKitUI
import SwiftUI
import NexusCore

/// Accepting what Claude prepared (review first, Nov 21): the ticked tasks go into the subject (or the Inbox) with a note pointing back
/// to the moment, the summary is written beside the recording, a class adds to its subject's teaching.md, and filed.json says what
/// was added. One Undo on the bar takes all of it back while nothing else changed those files.
@MainActor
enum RecordingFiler {
    static func accept(path: String, proposal p: Recordings.Proposal, store: NexusStore) {
        guard store.snapshot.readOnlyReason == nil else { store.problem = store.snapshot.readOnlyReason; return }
        let root = store.folder
        let editor = store.editor
        var changes: [Change] = []
        var added: [(id: String, file: String)] = []
        let ws = store.workstream(p.subject)
        let file = ws?.tasksFile ?? "inbox.yaml"
        do {
            for t in p.tasks where t.take {
                let s = DataFolder.load(root)
                let (c, id) = try editor.add(title: t.title, to: file, due: t.due, in: s, today: store.today)
                changes.append(c)
                added.append((id: id, file: file))
                let fresh = DataFolder.load(root)
                if let task = fresh.tasks[id] {
                    changes.append(try editor.setNote(task, Recordings.taskNote(t, title: p.title, path: path), in: fresh))
                }
            }
            guard var meta = RecordingService.shared.readMeta(path) else { throw RecError("its recording.json can't be read") }
            func put(_ rel: String, _ text: String, _ message: String) throws {
                let url = root.appendingPathComponent(rel)
                let before = (try? FolderAccess.read(url)) ?? ""
                try FolderAccess.write(url, text)
                var c = Change(file: rel, before: before, after: text, message: message)
                c.created = before.isEmpty
                changes.append(c)
            }
            var teaching: String?, teachingBefore: String?
            if let c = p.classNotes, p.takeTeaching, let ws {
                let rel = ws.folder + "/" + Recordings.teachingFile
                teachingBefore = (try? FolderAccess.read(root.appendingPathComponent(rel))) ?? ""
                let day = meta.startedDate.map { Recordings.localDay($0) } ?? store.today
                try put(rel, Recordings.addTeaching(teachingBefore, subjectName: ws.name, date: day, title: p.title, path: path, notes: c, moments: p.moments), "Teaching notes")
                teaching = rel
            }
            try put(path + "/" + Recordings.summaryFile, Recordings.summaryMarkdown(meta: meta, proposal: p, subjectName: ws?.name), "Summary")
            // the proposal as accepted (what was unticked stays unticked when the page shows it again)
            try put(path + "/" + Recordings.proposalFile, p.json.pretty + "\n", "Proposal")
            meta.title = p.title
            meta.subject = p.subject
            try put(path + "/" + Recordings.metaFile, meta.json.pretty + "\n", "Recording")
            let filed = Recordings.Filed(accepted: Recordings.iso(Date()), device: Device.name, subject: p.subject, tasks: added,
                                         teaching: teaching, teachingBefore: teachingBefore)
            try put(path + "/" + Recordings.filedFile, filed.json.pretty + "\n", "Filed")
        } catch {
            store.problem = "Couldn't file all of it: \(error)"
        }
        guard !changes.isEmpty else { return }
        // one Undo: each file once, from its first state to its last
        var order: [String] = [], first: [String: String] = [:], last: [String: Change] = [:]
        for c in changes {
            if first[c.file] == nil { first[c.file] = c.before; order.append(c.file) }
            last[c.file] = c
        }
        let merged: [Change] = order.map { f in
            var c = last[f]!
            c.before = first[f]!
            c.created = changes.first { $0.file == f }?.created ?? false
            return c
        }
        var head = merged[0]
        head.also = Array(merged.dropFirst())
        head.message = "Filed “\(p.title)”" + (added.isEmpty ? "" : ": \(added.count) task\(added.count == 1 ? "" : "s") in \(ws?.name ?? "the Inbox")")
        store.reload()
        store.didWrite(touched: order)
        store.toast = NexusStore.Toast(message: head.message, change: head)
        RecordingService.shared.changed()
    }
}

/// A date Claude heard, into the calendar: the system's new-event form, filled in, so nothing is added until Add is tapped there.
struct HeardDateSheet: UIViewControllerRepresentable {
    let store: EKEventStore
    let date: Recordings.ProposedDate
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let e = EKEvent(eventStore: store)
        e.title = date.what
        var start = Days.date(date.date) ?? Date()
        if let t = date.time {
            let p = t.split(separator: ":").compactMap { Int($0) }
            if p.count == 2 { start = Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: start) ?? start }
            e.startDate = start
            e.endDate = start.addingTimeInterval(3600)
        } else {
            e.isAllDay = true
            e.startDate = start
            e.endDate = start
        }
        if let c = store.defaultCalendarForNewEvents { e.calendar = c }
        vc.event = e
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { onDone() }
    }
}

/// The camera, for a photo while recording sound (Snap).
struct SnapCamera: UIViewControllerRepresentable {
    let onPhoto: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPhoto: onPhoto) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPhoto: (UIImage?) -> Void
        init(onPhoto: @escaping (UIImage?) -> Void) { self.onPhoto = onPhoto }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPhoto(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPhoto(nil) }
    }
}

/// The camera's live picture while filming a class.
struct FilmPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class Layer: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Layer {
        let v = Layer()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: Layer, context: Context) {}
}
