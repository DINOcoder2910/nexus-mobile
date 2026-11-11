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
        for (rel, text) in files {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: url.path) { continue } // never overwrite
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }
}
