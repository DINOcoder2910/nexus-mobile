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
            // Applications: two schools applying, a UC campus with its questions picked, one being considered, the overview and the Common App
            "applications/group.yaml": "label: Applications\norder: 3\nkind: school\ndefault: overview\n",
            "applications/overview/workstream.yaml": "id: overview\nname: Applications overview\nkind: project\nstatus: active\ninternal_rule: {for: \(d(20)), date: \(d(13))}\n",
            "applications/overview/tasks.yaml": "tasks:\n  - id: smap1\n    title: Ask Ms Rivera for the counsellor letter\n",
            "applications/common-app/workstream.yaml": "id: common-app\nname: Common App\nkind: project\nstatus: active\nessays:\n  - {id: ca1, title: Personal statement, lim: 650, fam: story}\n",
            "applications/common-app/tasks.yaml": "tasks:\n  - id: smap2\n    title: Finalise the personal statement\n    due: \(d(20))\n    est: 4h\n",
            "applications/northwestern/workstream.yaml": """
                id: northwestern
                name: Northwestern
                unitid: 147767
                tier: reach
                tier_level: 3
                status: active
                applying: true
                round: ed
                internal: \(d(13))
                research:
                  rounds:
                    ed: {dl: \(d(20)), rate: 23.4}
                    rd: {dl: \(d(66))}
                  profile:
                    checked: \(d(-3))
                    brief: A top engineering school on Lake Michigan, with a co-op option, small classes in the first year and strong ties to Chicago.
                    city: {name: "Evanston, IL", about: "A leafy lakeside suburb with a busy downtown.", metro: "Chicago, 25 minutes by train", weather: "cold, snowy winters; warm summers", cost: high}
                    opportunities: [Walter P. Murphy co-op program, Research from the first year, Chicago's tech and finance firms]
                    todo: [The lakefill and its beaches, Downtown Evanston, Chicago by the L]
                    greek: {men: 28, women: 33, of: 2024-25, src: "https://www.northwestern.edu/cds"}
                    concerns:
                      - {l: Quarter system, v: "Ten-week terms move fast: midterms come early and often."}
                      - {l: Cost, v: High sticker price; aid is need-based only.}
                    v: 2
                    sources: ["https://www.northwestern.edu/cds"]
                essays:
                  - {id: nort1, title: Why Northwestern, lim: 300, fam: why}
                  - {id: nort2, title: A community you belong to, lim: 300, fam: comm}
                requirements:
                  - {t: Common App (shared), done: true}
                  - {t: Supplemental essays}
                  - {t: Counsellor recommendation}
                  - {t: Teacher recommendation, done: true}
                  - {t: Test scores sent, na: true}

                """,
            "applications/northwestern/tasks.yaml": "tasks:\n  - id: smap3\n    title: Northwestern supplemental essays\n    due: \(d(20))\n    est: 3h\n    subtasks:\n      - {id: smap4, title: Why Northwestern draft, est: 90m}\n      - {id: smap5, title: Community essay draft}\n",
            "applications/columbia/workstream.yaml": "id: columbia\nname: Columbia\nunitid: 190150\ntier: dream\nstatus: active\napplying: true\nround: rd\nresearch:\n  rounds:\n    ed: {dl: \(d(20))}\n    rd: {dl: \(d(62))}\nessays:\n  - {id: colu1, title: Why Columbia, lim: 150, fam: why}\n  - {id: colu2, title: A time you faced adversity, lim: 200, fam: story}\nrequirements:\n  - {t: Common App (shared)}\n  - {t: Supplemental essays}\n",
            "applications/columbia/tasks.yaml": "tasks:\n  - id: smap6\n    title: Columbia short answers\n    est: 2h\n",
            "applications/ucla/workstream.yaml": "id: ucla\nname: UCLA\nunitid: 110662\ntier: target\nstatus: active\napplying: true\nround: rd\nresearch:\n  rounds:\n    rd: {dl: \(d(28))}\nessays:\n  - {id: uc-piq1, title: Leadership, lim: 350, fam: comm, sys: uc}\n  - {id: uc-piq6, title: Academic subject, lim: 350, fam: curio, sys: uc}\n",
            "applications/ucla/tasks.yaml": "tasks:\n  - id: smap7\n    title: UC Personal Insight Questions\n    est: 4h\n",
            "applications/tufts/workstream.yaml": "id: tufts\nname: Tufts\nunitid: 168148\ntier: target\nstatus: active\napplying: false\nresearch:\n  rounds:\n    ed: {dl: \(d(21))}\n    rd: {dl: \(d(66))}\n  prompts:\n    - {t: Why Tufts, lim: 150, unit: words, why: true}\n",
            "applications/tufts/tasks.yaml": "tasks: []\n",
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
