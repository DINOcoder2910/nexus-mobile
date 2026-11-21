import UIKit
import NexusCore

/// `-NexusTestRecordings` (UITests/RecordingsTests): sample data with a class and a meeting already recorded and prepared by Claude,
/// waiting for review, and recording that needs no microphone, speech model or Claude (a canned transcript and proposal).
@MainActor
enum RecordingDemo {
    static var on: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestRecordings") }

    static let transcript = Recordings.Transcript(language: "en-US", engine: "demo", segments: [
        .init(start: 2, end: 9, text: "Thanks for coming in. So you wanted to talk about the counsellor letter?", speaker: "S1"),
        .init(start: 10, end: 16, text: "Yes, I need it for the Common App, ideally before the end of the month.", speaker: "S2"),
        .init(start: 17, end: 30, text: "That's fine. Send me your activities list and a short paragraph on your essay by Friday, and I'll have it done for the twenty-eighth.", speaker: "S1"),
        .init(start: 31, end: 36, text: "Great, I'll send both on Friday.", speaker: "S2"),
    ])

    static var meetingProposal: Recordings.Proposal {
        let today = Days.today()
        return .init(title: "Counsellor letter with Ms Rivera", subject: "overview", people: ["Ms Rivera"], speakers: ["S1": "Ms Rivera", "S2": "You"],
                     summary: "Ms Rivera will write the counsellor letter for the Common App. She needs your **activities list** and a short paragraph on your essay first.",
                     decisions: ["The letter is done by the 28th"],
                     tasks: [.init(title: "Send Ms Rivera the activities list", due: Days.add(today, 2), at: 17),
                             .init(title: "Write a paragraph on the personal statement for Ms Rivera", due: Days.add(today, 2), at: 20)],
                     dates: [.init(what: "Counsellor letter ready", date: Days.add(today, 7))],
                     model: "claude-sonnet-5-5", made: Recordings.iso(Date()))
    }

    static let lessonTranscript = Recordings.Transcript(language: "en-US", engine: "demo", segments: [
        .init(start: 4, end: 14, text: "Right, today we're doing half-equations. Remember, oxidation states are just bookkeeping."),
        .init(start: 300, end: 318, text: "Atoms first, then oxygens with water, then hydrogens with H plus, then the charge with electrons. Say it with me."),
        .init(start: 754, end: 760, text: "Don't forget, this comes up every year in Paper 2."),
        .init(start: 1500, end: 1512, text: "Let's do permanganate going to manganese two plus, in acid."),
        .init(start: 2810, end: 2830, text: "For homework, questions one to six on the sheet. Quiz next Friday."),
    ])

    /// What Claude would say about each pin (the demo has no Claude).
    static func moments(_ pins: [Recordings.Pin]) -> [Recordings.Moment] {
        pins.map { p in
            let what: String
            switch p.kind {
            case "lost": what = "Balancing the charge: count the charges on each side, then add electrons to the more positive side until they match. In MnO₄⁻ + 8H⁺ → Mn²⁺ + 4H₂O the left is +7 and the right +2, so 5e⁻ go on the left."
            case "exam": what = "Mr Hale said balancing a half-equation in acid comes up every year in Paper 2, usually for 2 marks."
            case "homework": what = "Questions 1–6 on the half-equations sheet, before the quiz next Friday."
            default: what = "The order for every half-equation: atoms, then O with water, then H with H⁺, then charge with electrons."
            }
            return .init(at: p.at, kind: p.kind, what: what)
        }
    }

    /// The seeded class's pins: two from the buttons, one found by what was said.
    static let classPins: [Recordings.Pin] = [
        .init(at: 310, kind: "important", picture: "pictures/0310.jpg"),
        .init(at: 1505, kind: "lost", picture: "pictures/1505.jpg"),
        .init(at: 2810, kind: "homework", by: "auto", said: "For homework, questions one to six on the sheet."),
    ]

    static var classProposal: Recordings.Proposal {
        .init(title: "Redox: writing half-equations", subject: "chemistry-hl", people: ["Mr Hale"],
              summary: "How to write and balance half-equations in acidic solution, then combine them into a full redox equation.",
              tasks: [.init(title: "Do the half-equations sheet, Q1–6", due: Days.add(Days.today(), 3), at: 2810)],
              dates: [.init(what: "Redox quiz", date: Days.add(Days.today(), 6), time: "09:10", at: 2860)],
              classNotes: .init(unit: "R3.2", taught: "1. Oxidation states as bookkeeping\n2. Half-equations: atoms, then O with water, then H with H⁺, then charge with electrons\n3. Combining two half-equations",
                                examples: ["MnO₄⁻ → Mn²⁺ in acid", "Fe²⁺ → Fe³⁺, then combined with the permanganate"],
                                teaching: "Mr Hale uses the order **atoms, O, H, charge** every time and makes the class say it out loud. He checks each half-equation by adding up the charges on both sides, and warns that the electrons go on the left for a reduction."),
              model: "claude-sonnet-5-5", made: Recordings.iso(Date()))
    }

    /// At launch: the recordings, and `-NexusTestQuick` opens the quick page as the Action button does.
    static func atStart(_ store: NexusStore) {
        guard on else { return }
        seed(store)
        RecordingService.shared.changed()
        if ProcessInfo.processInfo.arguments.contains("-NexusTestQuick") { WindowRouter.shared.quick = true }
    }

    /// Two recordings waiting for review (made once per data folder).
    static func seed(_ store: NexusStore) {
        guard on else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        let root = store.folder
        guard Recordings.list(root).isEmpty else { return }
        let now = Date()
        func put(_ kind: Recordings.Kind, ago: Double, duration: Double, proposal: Recordings.Proposal, pictures: [(Double, String)], t: Recordings.Transcript,
                 pins: [Recordings.Pin] = []) {
            let start = now.addingTimeInterval(-ago)
            let path = Recordings.dir + "/" + Recordings.folderName(started: start, kind: kind)
            let folder = root.appendingPathComponent(path)
            var m = Recordings.Meta(id: Recordings.newId(), kind: kind, started: start, device: Device.name)
            m.duration = duration; m.state = "done"; m.language = "en-US"
            for (at, label) in pictures {
                let file = Recordings.pictureFile(at: at, taken: Set(m.pictures.map(\.file)))
                if let data = board(label) { try? FolderAccess.writeData(folder.appendingPathComponent(file), data) }
                m.pictures.append(.init(file: file, at: at))
            }
            m.pins = pins
            var proposal = proposal
            proposal.moments = moments(pins)
            try? FolderAccess.write(folder.appendingPathComponent(Recordings.metaFile), m.json.pretty + "\n")
            try? FolderAccess.write(folder.appendingPathComponent(Recordings.transcriptFile), t.json.pretty + "\n")
            try? FolderAccess.write(folder.appendingPathComponent(Recordings.transcriptText), t.markdown(title: m.title))
            try? FolderAccess.write(folder.appendingPathComponent(Recordings.proposalFile), proposal.json.pretty + "\n")
        }
        put(.lesson, ago: 3 * 3600, duration: 2940, proposal: classProposal, pictures: [(310, "Atoms → O (H₂O) → H (H⁺) → charge (e⁻)"), (1505, "MnO₄⁻ + 8H⁺ + 5e⁻ → Mn²⁺ + 4H₂O")],
            t: lessonTranscript, pins: classPins)
        put(.meeting, ago: 26 * 60, duration: 36, proposal: meetingProposal, pictures: [], t: transcript)
        AppServices.store.didWrite(touched: [Recordings.dir])
        store.reload()
    }

    /// A picture of a whiteboard with one line on it.
    static func board(_ text: String) -> Data? {
        let size = CGSize(width: 1200, height: 800)
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            UIColor(white: 0.96, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.75, alpha: 1).setStroke(); ctx.stroke(CGRect(x: 30, y: 30, width: 1140, height: 740))
            let p = NSMutableParagraphStyle(); p.alignment = .center
            (text as NSString).draw(in: CGRect(x: 60, y: 330, width: 1080, height: 200), withAttributes: [
                .font: UIFont.systemFont(ofSize: 54, weight: .medium), .foregroundColor: UIColor(red: 0.1, green: 0.25, blue: 0.6, alpha: 1), .paragraphStyle: p,
            ])
        }
        return img.jpegData(compressionQuality: 0.8)
    }
}
