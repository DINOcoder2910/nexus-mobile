import Foundation

/// A small data folder to try the app with before the real one is on the iPad, with dates around `today` so every screen has something.
public enum SampleFolder {
    public static func make(at root: URL, today: String) throws {
        let fm = FileManager.default
        func d(_ n: Int) -> String { Days.add(today, n) }
        let files: [String: String] = [
            "nexus.yaml": "nexus: 2\nfields: {}\nviewers: {}\n",
            "inbox.yaml": "tasks:\n  - id: smp1\n    title: Ask about the field trip form\n    added: \(today)\n  - id: smp2\n    title: Learn to juggle\n    someday: true\n",
            "classes/group.yaml": "label: Classes\norder: 1\nkind: class\n",
            "classes/physics-hl/workstream.yaml": "id: physics-hl\nname: Physics HL\ncolor: blue\naliases: [phys]\nstatus: active\n",
            "classes/physics-hl/tasks.yaml": """
                tasks:
                  - id: smp3
                    title: Physics HW sheet
                    due: \(d(2))
                    key: true
                    est: 2h
                    subtasks:
                      - id: smp4
                        title: Q1–5
                        plan: [\(today) 16:00]
                        est: 45m
                      - id: smp5
                        title: Q6–10
                        plan: [\(d(1))]
                        est: 45m
                  - id: smp6
                    title: Read 4.2 on waves
                    plan: [\(d(-2))]
                    est: 30m
                  - id: smp7
                    title: Lab report
                    due: \(d(9))
                    waiting: {on: Ms Settle, since: \(d(-3))}

                """,
            "classes/physics-hl/notes.md": "# Physics HL\n\nUnit 4: waves. Test in two weeks.\n\n## Decisions\n\n- Do past papers on Sundays.\n",
            "classes/chemistry-hl/workstream.yaml": "id: chemistry-hl\nname: Chemistry HL\ncolor: green\nstatus: active\n",
            "classes/chemistry-hl/tasks.yaml": """
                tasks:
                  - id: smp8
                    title: Redox worksheet
                    plan: [\(today)]
                    est: 1h
                  - id: smp9
                    title: Flashcards for R3.2
                    every: {freq: week, on: [\(["sun", "mon", "tue", "wed", "thu", "fri", "sat"][Days.weekday(today)])]}
                  - id: smpa
                    title: Unit test
                    due: \(d(5))
                    key: true
                    plan: [\(d(3)), \(d(4))]

                """,
            "projects/group.yaml": "label: Projects\norder: 2\nkind: project\n",
            "projects/nexus/workstream.yaml": "id: nexus\nname: Nexus\ncolor: violet\nstatus: active\n",
            "projects/nexus/tasks.yaml": "tasks:\n  - id: smpb\n    title: Try the iPad planner\n    plan: [\(today)]\n    est: 15m\n  - id: smpc\n    title: Copy my real data folder over\n",
        ]
        var all = files.mapValues { Data($0.utf8) }
        for (rel, data) in study(today: today) { all[rel] = data }
        for (rel, data) in all {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: url.path) { continue } // never overwrite
            try data.write(to: url, options: .atomic)
        }
    }

    // MARK: Chemistry HL's study folder

    static let chem = "classes/chemistry-hl"
    static let sheetsDir = chem + "/files/Sheets"

    /// A study folder as the laptop's Study tab makes one: study.yaml (the sheets in files/Sheets), the syllabus units with how far
    /// each is covered, a deck of acids and bases with a practice list, and a few practice sheets filed in the folder's convention.
    static func study(today: String) -> [String: Data] {
        var out: [String: Data] = [:]
        func text(_ rel: String, _ t: String) { out[chem + "/" + rel] = Data(t.utf8) }
        text("study/study.yaml", "sheets: files/Sheets\n")
        let units: [(String, String, String)] = [
            ("S1.1", "Introduction to the particulate nature of matter", "done"), ("S1.2", "The nuclear atom", "done"),
            ("S1.3", "Electron configurations", "done"), ("S1.4", "Counting particles by mass: the mole", "done"),
            ("S1.5", "Ideal gases", "partial"),
            ("S2.1", "The ionic model", "done"), ("S2.2", "The covalent model", "done"), ("S2.3", "The metallic model", "partial"),
            ("S2.4", "From models to materials", "not-yet"),
            ("S3.1", "The periodic table: classification of elements", "partial"), ("S3.2", "Functional groups: classification of organic compounds", "not-yet"),
            ("R1.1", "Measuring enthalpy changes", "done"), ("R1.2", "Energy cycles in reactions", "done"),
            ("R1.3", "Energy from fuels", "not-yet"), ("R1.4", "Entropy and spontaneity", "partial"),
            ("R2.1", "How much? The amount of chemical change", "done"), ("R2.2", "How fast? The rate of chemical change", "partial"),
            ("R2.3", "How far? The extent of chemical change", "not-yet"),
            ("R3.1", "Proton transfer reactions", "done"), ("R3.2", "Electron transfer reactions", "partial"),
            ("R3.3", "Electron sharing reactions", "not-yet"), ("R3.4", "Electron-pair sharing reactions", "not-yet"),
        ]
        text("study/units.yaml", "units:\n" + units.map { u in
            "  - code: \(u.0)\n    title: '\(u.1.replacingOccurrences(of: "'", with: "''"))'\n    status: \(u.2)\n" + (u.0 == "R3.2" ? "    notes: Oxidation states done; electrochemical cells next.\n    evidence: Redox worksheet, class notes\n" : "")
        }.joined())
        let o = "[strong acid, weak acid, strong base, weak base]"
        text("study/decks/acids.yaml", """
            id: acids
            title: Acids and bases
            description: Which acids and bases are strong, and which are weak.
            columns: [{key: name, label: Name}, {key: type, label: Type}]
            cards:
            - {id: hx, fields: {name: 'HCl, HBr, HI', type: strong acid}, front: 'hydrohalic acids (not HF)', back: strong acid, covers: [HCl, HBr, HI], options: \(o)}
            - {id: oxo, fields: {name: 'H₂SO₄, HNO₃', type: strong acid}, front: 'sulfuric and nitric acid', back: strong acid, covers: [H₂SO₄, HNO₃], options: \(o)}
            - {id: g1, fields: {name: group 1 hydroxides, type: strong base}, front: group 1 hydroxides, back: strong base, covers: [LiOH, NaOH, KOH], note: Fully dissociated in water., options: \(o)}
            - {id: carb, fields: {name: carboxylic acids, type: weak acid}, front: carboxylic acids, back: weak acid, covers: [ethanoic acid, methanoic acid], options: \(o)}
            - {id: hf, fields: {name: HF, type: weak acid}, front: 'hydrofluoric acid, HF', back: weak acid, note: The H–F bond is strong., options: \(o)}
            - {id: nh3, fields: {name: ammonia and amines, type: weak base}, front: 'ammonia and amines', back: weak base, covers: [NH₃, CH₃NH₂], options: \(o)}
            practice:
            - {id: p-hcl, level: required, name: hydrochloric acid, formula: HCl, answer: strong acid, rule: hx}
            - {id: p-h2so4, level: required, name: sulfuric acid, formula: H₂SO₄, answer: strong acid, rule: oxo}
            - {id: p-hno3, level: required, name: nitric acid, formula: HNO₃, answer: strong acid, rule: oxo}
            - {id: p-naoh, level: required, name: sodium hydroxide, formula: NaOH, answer: strong base, rule: g1}
            - {id: p-koh, level: common, name: potassium hydroxide, formula: KOH, answer: strong base, rule: g1}
            - {id: p-eth, level: required, name: ethanoic acid, formula: CH₃COOH, answer: weak acid, rule: carb, note: pKa 4.76.}
            - {id: p-meth, level: common, name: methanoic acid, formula: HCOOH, answer: weak acid, rule: carb}
            - {id: p-hf, level: common, name: hydrofluoric acid, formula: HF, answer: weak acid, rule: hf}
            - {id: p-nh3, level: required, name: ammonia, formula: NH₃, answer: weak base, rule: nh3}
            - {id: p-ma, level: extra, name: methylamine, formula: CH₃NH₂, answer: weak base, rule: nh3}

            """)
        // the sheets, in the folder's convention: unit folder / "Title — details [syllabus]" / the paper and its markscheme
        let sheets: [(String, String, [String])] = [
            ("01 Structure 1 — Models of matter/Mole & Atomic Structure — HL test, 40 mk, 60 min [pre-2025]", "Atomic structure test", ["Mole & atomic structure test", "1. Calculate the number of moles in 4.0 g of NaOH. [2]", "2. State the electron configuration of Fe3+. [1]"]),
            ("02 Structure 2 — Bonding/Bonding — HL test, 35 mk, 50 min, 9 pp [2025]", "Bonding", ["Bonding test", "1. Draw the Lewis structure of SO2 and predict its shape. [3]", "2. Explain why graphite conducts electricity. [2]"]),
            ("05 Reactivity 1 — Energetics/Hess — MCQ [2025]", "Hess MCQ", ["Hess's law: multiple choice", "1. Which is the enthalpy change of formation of CO2?", "2. Use the cycle to find the enthalpy of reaction."]),
            ("05 Reactivity 1 — Energetics/Energetics — HL test, 30 mk, no MS [2025]", "Energetics test", ["Energetics test", "1. Define standard enthalpy of combustion. [2]", "2. Draw a Born-Haber cycle for MgO. [4]"]),
            ("06 Reactivity 2 — Rates/Rates — quiz, 10 Q, 15 min [2025]", "Rates quiz", ["Rates of reaction quiz", "1. State two factors that increase the rate of a reaction.", "2. Sketch a Maxwell-Boltzmann distribution."]),
            ("08 Reactivity 3 — Acids and bases/Acids — Paper 2 structured, 40 mk [2025]", "Acids paper 2", ["Acids and bases: paper 2", "1. Calculate the pH of 0.010 mol dm-3 HCl. [1]", "2. Explain why ethanoic acid is a weak acid. [2]"]),
            ("09 Multi-Topic Papers/Kinetics + Equilibrium — SL MCQ, 30 mk, no MS [pre-2025]", "Kinetics MCQ", ["Kinetics and equilibrium MCQ", "1. Which change increases the value of Kc?", "2. Which is the rate expression?"]),
        ]
        for (dir, name, lines) in sheets {
            out[sheetsDir + "/" + dir + "/" + name + ".pdf"] = pdf(lines)
            if !dir.contains("no MS") { out[sheetsDir + "/" + dir + "/" + name + " MS.pdf"] = pdf(["Markscheme: " + lines[0], "1. Answers as in the mark scheme."]) }
        }
        let key = "05 Reactivity 1 — Energetics/Hess — MCQ [2025]"
        text("study/sheets.yaml", SheetIndex.serialize([key: SheetIndex.merge(nil, file: "Hess MCQ.pdf", notes: "Questions 7 and 12 need cycles we have not done yet.", units: ["R1.2"], filed: today)]))
        return out
    }

    /// A small text PDF (one A4 page, Helvetica, ASCII), for the sample sheets and the upload's demo.
    public static func pdf(_ lines: [String]) -> Data {
        func esc(_ s: String) -> String {
            String(s.unicodeScalars.map { $0.isASCII ? Character($0) : "?" }).replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        }
        var stream = "BT /F1 18 Tf 56 770 Td (\(esc(lines.first ?? ""))) Tj /F1 12 Tf"
        for l in lines.dropFirst() { stream += " 0 -26 Td (\(esc(l))) Tj" }
        stream += " ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, o) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(o)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { out += String(format: "%010d 00000 n \n", o) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }
}
