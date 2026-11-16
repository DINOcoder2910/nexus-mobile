import XCTest
@testable import NexusCore

/// Study's practice sheets, units, Practice classifying and Upload a sheet on the iPhone and iPad: each checked against what the laptop's
/// own studysheets.js, studyupload.js, studyread.js and studydeck.js give for the same inputs (SheetsGolden.swift, made by
/// tools/study-golden/gen-sheets.mjs), then what only the phone and iPad add.
final class SheetsTests: XCTestCase {
    lazy var g: JSONValue = (try? JSONValue.parse(sheetsGolden)) ?? .null

    private func s(_ v: JSONValue?) -> String? { if case .string(let x)? = v { return x }; return nil }
    private func i(_ v: JSONValue?) -> Int? { v?.number.map { Int($0) } }
    private func strs(_ v: JSONValue?) -> [String] { v?.array?.compactMap { $0.string } ?? [] }
    private func rows(_ key: String) -> [[JSONValue]] { g[key]?.array?.compactMap { $0.array } ?? [] }

    private lazy var models: [(root: String, model: StudySheets.Model)] = (g["models"]?.array ?? []).map { m in
        let root = s(m["root"]) ?? ""
        return (root, StudySheets.build(strs(m["files"]), root: root))
    }

    private func group(_ v: JSONValue?) -> StudySheets.Group? {
        guard let v, v != .null else { return nil }
        return StudySheets.Group(path: s(v["path"]) ?? "", label: s(v["label"]) ?? "", code: s(v["code"]))
    }

    func testGoldenLoads() {
        XCTAssertEqual(models.count, 5)
        XCTAssertGreaterThan(rows("readAnswer").count, 10)
    }

    // MARK: names

    func testSheetNames() {
        for r in rows("sheetName") {
            let name = s(r[0])!, want = r[1], f = StudySheets.parseSheetName(name)
            XCTAssertEqual(f.title, s(want["title"]), name)
            XCTAssertEqual(f.details, strs(want["details"]), name)
            XCTAssertEqual(f.era, s(want["era"]), name)
            XCTAssertEqual(f.copies, i(want["copies"]), name)
            XCTAssertEqual(f.ms, s(want["ms"]), name)
            XCTAssertEqual(f.meta, want["meta"]?.bool, name)
            XCTAssertEqual(f.marks, i(want["marks"]), name)
            XCTAssertEqual(f.pages, i(want["pages"]), name)
            XCTAssertEqual(f.minutes, i(want["minutes"]), name)
            XCTAssertEqual(f.questions, i(want["questions"]), name)
            XCTAssertEqual(f.level, s(want["level"]), name)
            XCTAssertEqual(f.kind, s(want["kind"]), name)
        }
        for r in rows("kindOf") { XCTAssertEqual(StudySheets.kindOf(s(r[0])!, s(r[1])!), s(r[2]), "\(r)") }
        for r in rows("fileRole") { XCTAssertEqual(StudySheets.fileRole(s(r[0])!), s(r[1]), s(r[0])!) }
        for r in rows("unitOfFolder") {
            let u = StudySheets.unitOfFolder(s(r[0])!)
            XCTAssertEqual(u.code, s(r[1]["code"]), s(r[0])!); XCTAssertEqual(u.label, s(r[1]["label"]), s(r[0])!)
        }
        for r in rows("codesIn") { XCTAssertEqual(StudySheets.codesIn(s(r[0])!), strs(r[1]), s(r[0])!) }
        for r in rows("codesFromTitle") { XCTAssertEqual(StudySheets.codesFromTitle(s(r[0])!), strs(r[1]), s(r[0])!) }
        for r in rows("stemOf") { XCTAssertEqual(StudySheets.stemOf(s(r[0])!), s(r[1]), s(r[0])!) }
        for r in rows("splitTop") { XCTAssertEqual(StudySheets.splitTop(s(r[0])!), strs(r[1]), s(r[0])!) }
        for r in rows("safeName") { XCTAssertEqual(StudySheets.safeName(s(r[0])!), s(r[1]), s(r[0])!) }
        for r in rows("sheetFolderName") {
            let p = r[0]
            let details = p["details"]?.array.map { $0.compactMap(\.string).joined(separator: ", ") } ?? s(p["details"]) ?? ""
            XCTAssertEqual(StudySheets.sheetFolderName(title: s(p["title"]) ?? "", details: details, ms: s(p["ms"]) ?? "", copies: i(p["copies"]) ?? 1, era: s(p["era"])), s(r[1]), "\(p.text)")
        }
        for r in rows("fileNameFor") { XCTAssertEqual(StudySheets.fileNameFor(s(r[0])!, role: s(r[1])!), s(r[2]), s(r[0])!) }
        for r in rows("safePath") { XCTAssertEqual(StudySheets.safePath(s(r[0])!), s(r[1]), s(r[0])!) }
        for r in rows("relIn") { XCTAssertEqual(StudySheets.relIn(s(r[0])!, s(r[1])!), s(r[2])) }
        for r in rows("newUnitFolderName") {
            XCTAssertEqual(StudySheets.newUnitFolderName(models[i(r[0])!].model.groups, label: s(r[1])!, root: s(r[2])!), s(r[3]))
        }
    }

    // MARK: the model

    func testModels() {
        for (k, m) in (g["models"]?.array ?? []).enumerated() {
            let got = models[k].model
            let want = m["sheets"]?.array ?? []
            XCTAssertEqual(got.sheets.map(\.path), want.compactMap { s($0["path"]) }, "model \(k): the sheets and their order")
            XCTAssertEqual(got.groups.map(\.path), (m["groups"]?.array ?? []).compactMap { s($0["path"]) }, "model \(k): the groups")
            for (a, b) in zip(got.groups, m["groups"]?.array ?? []) { XCTAssertEqual(a, group(b)) }
            for (a, b) in zip(got.sheets, want) {
                let at = "model \(k) \(a.path)"
                XCTAssertEqual(a.id, s(b["id"]), at); XCTAssertEqual(a.dir, b["dir"]?.bool, at); XCTAssertEqual(a.group, group(b["group"]), at)
                XCTAssertEqual(a.title, s(b["title"]), at); XCTAssertEqual(a.details, strs(b["details"]), at); XCTAssertEqual(a.era, s(b["era"]), at)
                XCTAssertEqual(a.copies, i(b["copies"]), at); XCTAssertEqual(a.ms, s(b["ms"]), at); XCTAssertEqual(a.meta, b["meta"]?.bool, at)
                XCTAssertEqual(a.marks, i(b["marks"]), at); XCTAssertEqual(a.pages, i(b["pages"]), at); XCTAssertEqual(a.minutes, i(b["minutes"]), at)
                XCTAssertEqual(a.questions, i(b["questions"]), at); XCTAssertEqual(a.level, s(b["level"]), at); XCTAssertEqual(a.kind, s(b["kind"]), at)
                XCTAssertEqual(a.files.map(\.path), (b["files"]?.array ?? []).compactMap { s($0["path"]) }, at)
                XCTAssertEqual(a.files.map(\.role), (b["files"]?.array ?? []).compactMap { s($0["role"]) }, at)
                XCTAssertEqual(a.codes, strs(b["codes"]), at)
                for (c, how) in b["codeFrom"]?.object ?? [] { XCTAssertEqual(a.codeFrom[c], s(how), at + " " + c) }
                XCTAssertEqual(a.codeFrom.count, b["codeFrom"]?.object?.count, at)
                XCTAssertEqual(a.search, s(b["search"]), at)
            }
        }
    }

    func testUnitsFiltersSorts() {
        for r in rows("forUnit") {
            let m = models[i(r[0])!].model
            XCTAssertEqual(StudySheets.sheetsFor(unit: s(r[1])!, in: m.sheets, extra: strs(r[2])).map(\.path), strs(r[3]), "\(r[0].text) \(r[1].text)")
        }
        for r in rows("filter") {
            let m = models[i(r[0])!].model, f = r[1]
            let filter = StudySheets.Filter(q: s(f["q"]) ?? "", unit: s(f["unit"]) ?? "", kind: s(f["kind"]) ?? "", era: s(f["era"]) ?? "", ms: s(f["ms"]) ?? "", level: s(f["level"]) ?? "")
            XCTAssertEqual(StudySheets.filter(m.sheets, filter).map(\.path), strs(r[2]), "\(r[0].text) \(f.text)")
        }
        for r in rows("sort") {
            XCTAssertEqual(StudySheets.sort(models[i(r[0])!].model.sheets, by: s(r[1])!).map(\.path), strs(r[2]), "\(r[0].text) \(r[1].text)")
        }
        for r in rows("facts") {
            guard let sheet = models[i(r[0])!].model.sheets.first(where: { $0.path == s(r[1]) }) else { XCTFail("no sheet \(r[1].text)"); continue }
            XCTAssertEqual(StudySheets.factsLine(sheet), s(r[2])); XCTAssertEqual(StudySheets.msLabel(sheet.ms), s(r[3]))
        }
    }

    // MARK: units, the config, Practice classifying

    func testConfigAndUnits() {
        for r in rows("config") {
            let c = StudyUnits.parseConfig(s(r[0]))
            XCTAssertEqual(c.sheets, s(r[1]["sheets"]), s(r[0])!); XCTAssertEqual(c.language, s(r[1]["language"]), s(r[0])!)
        }
        for r in rows("units") {
            let text = s(r[0])!
            switch StudyUnits.parseUnits(text) {
            case .ok(let units):
                XCTAssertEqual(r[1].bool, true, text)
                let want = r[3].array ?? []
                XCTAssertEqual(units.count, want.count, text)
                for (a, b) in zip(units, want) {
                    XCTAssertEqual(a.code, s(b["code"]), text); XCTAssertEqual(a.title, s(b["title"]), text); XCTAssertEqual(a.status, s(b["status"]), text)
                    XCTAssertEqual(a.evidence, s(b["evidence"]), text); XCTAssertEqual(a.notes, s(b["notes"]), text); XCTAssertEqual(a.sheets, strs(b["sheets"]), text)
                }
                let themes = StudyUnits.themesOf(units)
                XCTAssertEqual(themes.map(\.code), (r[4].array ?? []).compactMap { $0.array.flatMap { s($0[0]) } }, text)
                XCTAssertEqual(themes.map(\.title), (r[4].array ?? []).compactMap { $0.array.flatMap { s($0[1]) } }, text)
                XCTAssertEqual(themes.map { $0.units.map(\.code) }, (r[4].array ?? []).compactMap { $0.array.map { strs($0[2]) } }, text)
            case .failed(let why):
                XCTAssertEqual(r[1].bool, false, text)
                let want = s(r[2]) ?? ""
                // the parser's own words differ (yaml vs Yams); the start is the laptop's
                if want.hasPrefix("study/units.yaml does not parse") { XCTAssertTrue(why.hasPrefix("study/units.yaml does not parse"), why) } else { XCTAssertEqual(why, want) }
            }
        }
        for (k, v) in g["themes"]?.object ?? [] { XCTAssertEqual(StudyUnits.themes[k], s(v), k) }
        XCTAssertEqual(StudyUnits.statuses.map(\.id), (g["status"]?.object ?? []).map(\.0))
        XCTAssertEqual(StudyUnits.statuses.map(\.label), (g["status"]?.object ?? []).compactMap { s($0.1) })
    }

    func testPracticeClassifying() throws {
        for p in g["practice"]?.array ?? [] {
            let deck = try XCTUnwrap(StudyDeck.parse(s(p["yaml"])!, fileId: s(p["id"])!).deck)
            let want = p["items"]?.array ?? []
            XCTAssertEqual(deck.practice.map(\.id), want.compactMap { s($0["id"]) })
            for (a, b) in zip(deck.practice, want) {
                XCTAssertEqual(a.name, s(b["name"])); XCTAssertEqual(a.formula, s(b["formula"])); XCTAssertEqual(a.answer, s(b["answer"]))
                XCTAssertEqual(a.rule, s(b["rule"])); XCTAssertEqual(a.level, s(b["level"])); XCTAssertEqual(a.note, s(b["note"]))
            }
            XCTAssertEqual(StudyUnits.practiceOptions(deck), strs(p["options"]))
            for r in p["rounds"]?.array?.compactMap(\.array) ?? [] {
                let ids: [String]? = r[1] == .null ? nil : strs(r[1])
                XCTAssertEqual(StudyUnits.practiceRound(deck, level: s(r[0])!, ids: ids, seed: s(r[2])!), strs(r[3]), "\(r[0].text) \(r[2].text)")
            }
            for r in p["checks"]?.array?.compactMap(\.array) ?? [] {
                let item = try XCTUnwrap(deck.practice.first { $0.id == s(r[0]) })
                XCTAssertEqual(StudyUnits.practiceCheck(s(r[1])!, item).rawValue, s(r[2]), "\(r[0].text) \(r[1].text)")
            }
            for r in p["rules"]?.array?.compactMap(\.array) ?? [] {
                let item = try XCTUnwrap(deck.practice.first { $0.id == s(r[0]) })
                XCTAssertEqual(StudyUnits.ruleOf(deck, item)?.id, s(r[1]))
            }
        }
    }

    // MARK: the upload

    func testFolderSummaryAndPaths() {
        for r in rows("folderSummary") {
            let k = i(r[0])!
            let focus: [String]? = r[1] == .null ? nil : strs(r[1])
            XCTAssertEqual(StudyUpload.folderSummary(models[k].model, root: models[k].root, focus: focus), s(r[2]), "model \(k) \(r[1].text)")
        }
        for r in rows("targetPath") {
            let p = r[1]
            let pl = StudyUpload.Placement(unitFolder: s(p["unitFolder"]) ?? "", existingSheet: s(p["existingSheet"]), title: s(p["title"]) ?? "", details: s(p["details"]) ?? "",
                                           ms: s(p["ms"]) ?? "", era: s(p["era"]), fileName: s(p["fileName"]) ?? "")
            XCTAssertEqual(StudyUpload.targetPath(root: s(r[0])!, pl, max: i(r[2])), s(r[3]), "\(r[2].text)")
        }
        for r in rows("newUnitParent") { XCTAssertEqual(StudyUpload.newUnitParent(models[i(r[0])!].model, root: models[i(r[0])!].root), s(r[1])) }
        for r in rows("sameNameFiles") { XCTAssertEqual(StudyUpload.sameNameFiles(models[i(r[0])!].model, s(r[1])!), strs(r[2]), s(r[1])!) }
        for r in rows("shingles") {
            let a = StudyUpload.shingles(s(r[0])!), b = StudyUpload.shingles(s(r[1])!)
            XCTAssertEqual(a.count, i(r[2])); XCTAssertEqual(b.count, i(r[3]))
            XCTAssertEqual(StudyUpload.overlap(a, b), r[4].number ?? -1, accuracy: 1e-9)
            for x in strs(r[5]) { XCTAssertTrue(a.contains(x), x) }
        }
        let near = g["near"]?.array ?? []
        XCTAssertEqual(StudyUpload.near, near[0].number); XCTAssertEqual(StudyUpload.minShingles, i(near[1]))
        XCTAssertEqual(StudyUpload.digestMax, i(near[2])); XCTAssertEqual(StudyUpload.pageThin, i(near[3]))
        let props = g["props"]?.array ?? []
        for r in rows("compareCandidates") {
            let k = i(r[0])!, pv = props[i(r[2])!]
            var prop: StudyUpload.Proposal?
            if pv != .null {
                var p = StudyUpload.Proposal()
                p.unitFolder = s(pv["unitFolder"]) ?? ""; p.role = s(pv["role"]) ?? ""
                p.duplicates = (pv["duplicates"]?.array ?? []).map { StudyUpload.Duplicate(path: s($0["path"]) ?? "", why: s($0["why"]) ?? "") }
                prop = p
            }
            XCTAssertEqual(StudyUpload.compareCandidates(models[k].model, root: models[k].root, proposal: prop, fileName: s(r[1])!), strs(r[3]), "\(r[1].text) \(r[2].text)")
            XCTAssertEqual(StudyUpload.compareCandidates(models[k].model, root: models[k].root, proposal: prop, fileName: s(r[1])!, max: 2), strs(r[4]))
        }
    }

    func testReadingAPaper() {
        for r in rows("thin") {
            let pages = strs(r[0])
            XCTAssertEqual(StudyUpload.isThin(pages), r[1].bool, "\(pages.map(\.count))")
            XCTAssertEqual(StudyUpload.thinPages(pages), (r[2].array ?? []).compactMap(i))
            XCTAssertEqual(StudyUpload.thinPages(pages, max: 2), (r[3].array ?? []).compactMap(i))
        }
        for r in rows("ocrFirst") {
            XCTAssertEqual(StudyUpload.ocrFirst((r[0].array ?? []).compactMap(i), pages: i(r[1])!, k: i(r[2])!), (r[3].array ?? []).compactMap(i))
        }
        for r in rows("keyLines") {
            XCTAssertEqual(StudyUpload.keyLines(s(r[0])!), strs(r[1]), s(r[0])!)
            XCTAssertEqual(StudyUpload.keyLines(s(r[0])!, max: 2), strs(r[2]))
        }
        for r in rows("digest") {
            let pages = strs(r[0])
            let got = r[1] == .null ? StudyUpload.digest(pages) : StudyUpload.digest(pages, cap: i(r[1])!)
            XCTAssertEqual(got, s(r[2]), "\(pages.count) pages, cap \(r[1].text)")
        }
        for r in rows("keywords") {
            let pages = strs(r[0])
            let got = StudyUpload.keywordCounts(pages)
            XCTAssertEqual(got.map(\.code), (r[1].array ?? []).compactMap { $0.array.flatMap { s($0[0]) } })
            XCTAssertEqual(got.map(\.n), (r[1].array ?? []).compactMap { $0.array.flatMap { i($0[1]) } })
            XCTAssertEqual(StudyUpload.keywordHint(pages), s(r[2]))
        }
        for r in rows("focusFolders") {
            let k = i(r[0])!
            XCTAssertEqual(StudyUpload.focusFolders(models[k].model, root: models[k].root, pages: strs(r[1])), strs(r[2]), "\(r[1].text)")
        }
        for r in rows("readPrompt") {
            let o = r[0]
            let got = StudyUpload.readPrompt(fileName: s(o["fileName"]) ?? "", text: s(o["text"]) ?? "", hint: s(o["hint"]) ?? "", summary: s(o["summary"]) ?? "",
                                             units: s(o["units"]) ?? "", how: s(o["how"]) ?? "text", pages: i(o["pages"]) ?? 0,
                                             images: (o["images"]?.array ?? []).compactMap(i), note: s(o["note"]) ?? "")
            XCTAssertEqual(got, s(r[1]))
        }
        for r in rows("picturePages") {
            XCTAssertEqual(StudyUpload.picturePages(i(r[0])!, sent: (r[1].array ?? []).compactMap(i), extra: i(r[2])!), (r[3].array ?? []).compactMap(i), "\(r[0].text) \(r[1].text)")
        }
        for r in rows("nextImagePages") {
            XCTAssertEqual(StudyUpload.nextImagePages(i(r[0])!, sent: (r[1].array ?? []).compactMap(i)), (r[2].array ?? []).compactMap(i))
        }
        XCTAssertEqual(try? JSONValue.parse(StudyUpload.schemaJSON), g["schema"])
        XCTAssertEqual(StudyUpload.kinds, strs(g["kinds"]))
        XCTAssertEqual(StudySheets.kinds, strs(g["sheetKinds"]))
        XCTAssertEqual(StudySheets.sorts.map(\.id), (g["sorts"]?.object ?? []).map(\.0))
        XCTAssertEqual(StudySheets.sorts.map(\.label), (g["sorts"]?.object ?? []).compactMap { s($0.1) })
        XCTAssertEqual(StudySheets.eras.map(\.label), (g["eras"]?.object ?? []).compactMap { s($0.1) })
    }

    func testClaudesAnswer() {
        for r in rows("readAnswer") {
            let k = i(r[2])!, at = "\(r[0].text) \(r[1].text)"
            let got = StudyUpload.readAnswer(r[0], fileName: s(r[1])!, model: models[k].model, root: s(r[3])!)
            let want = r[4]
            switch got {
            case .failed(let why):
                XCTAssertEqual(want["ok"]?.bool, false, at); XCTAssertEqual(why, s(want["error"]), at)
            case .ok(let p):
                XCTAssertEqual(want["ok"]?.bool, true, at)
                let w = want["proposal"] ?? .null
                XCTAssertEqual(p.summary, s(w["summary"]), at); XCTAssertEqual(p.role, s(w["role"]), at); XCTAssertEqual(p.unitFolder, s(w["unitFolder"]), at)
                XCTAssertEqual(p.unitIsNew, w["unitIsNew"]?.bool, at); XCTAssertEqual(p.multi, w["multi"]?.bool, at); XCTAssertEqual(p.existingSheet, s(w["existingSheet"]), at)
                XCTAssertEqual(p.title, s(w["title"]), at); XCTAssertEqual(p.details, s(w["details"]), at); XCTAssertEqual(p.era, s(w["era"]), at)
                XCTAssertEqual(p.ms, s(w["ms"]), at); XCTAssertEqual(p.codes, strs(w["codes"]), at)
                XCTAssertEqual(p.sections.map(\.name), (w["sections"]?.array ?? []).compactMap { s($0["name"]) }, at)
                XCTAssertEqual(p.sections.map(\.codes), (w["sections"]?.array ?? []).map { strs($0["codes"]) }, at)
                XCTAssertEqual(p.fileName, s(w["fileName"]), at)
                XCTAssertEqual(p.duplicates.map(\.path), (w["duplicates"]?.array ?? []).compactMap { s($0["path"]) }, at)
                XCTAssertEqual(p.duplicates.map(\.why), (w["duplicates"]?.array ?? []).compactMap { s($0["why"]) }, at)
                XCTAssertEqual(p.kind, s(w["kind"]), at); XCTAssertEqual(p.level, s(w["level"]), at)
                XCTAssertEqual(p.marks, i(w["marks"]), at); XCTAssertEqual(p.minutes, i(w["minutes"]), at); XCTAssertEqual(p.pages, i(w["pages"]), at)
                XCTAssertEqual(p.notes, s(w["notes"]), at); XCTAssertEqual(p.unsure, w["unsure"]?.bool, at); XCTAssertEqual(p.reason, s(w["reason"]), at)
            }
        }
        for r in rows("answerFromText") {
            let got = StudyUpload.answerFromText(s(r[0])!)
            XCTAssertEqual(got ?? .null, r[1], s(r[0])!)
        }
        for r in rows("folderFor") {
            let k = i(r[1])!
            let f = StudyUpload.folderFor(strs(r[0]), models[k].model, root: models[k].root)
            XCTAssertEqual(f.folder, s(r[2]["folder"]), "\(r[0].text)"); XCTAssertEqual(f.multi, r[2]["multi"]?.bool, "\(r[0].text)")
        }
    }

    // MARK: study/sheets.yaml

    private func entries(_ v: JSONValue?) -> [String: SheetIndex.Entry]? {
        guard let o = v?.object else { return nil }
        var out: [String: SheetIndex.Entry] = [:]
        for (k, e) in o { out[k] = entry(e) }
        return out
    }
    private func entry(_ e: JSONValue) -> SheetIndex.Entry {
        SheetIndex.Entry(notes: (e["notes"]?.object ?? []).map { ($0.0, s($0.1) ?? "") }, units: strs(e["units"]), filed: s(e["filed"]) ?? "")
    }

    func testSheetIndex() {
        for r in rows("sheetIndex") {
            let text = s(r[0])!
            XCTAssertEqual(SheetIndex.parseStrict(text), r[1] == .null ? nil : entries(r[1]), text)
            XCTAssertEqual(SheetIndex.parse(text), entries(r[2]) ?? [:], text)
        }
        for r in rows("sheetIndexText") {
            let idx = entries(r[0]) ?? [:]
            let mine = SheetIndex.serialize(idx)
            // what the laptop wrote and what this writes read back the same (the laptop's own reader, ported, and Yams)
            XCTAssertEqual(SheetIndex.parse(mine), SheetIndex.parse(s(r[1])!), mine)
            XCTAssertEqual(SheetIndex.parse(mine), idx.filter { !$0.value.notes.filter { !$0.1.isEmpty }.isEmpty || !$0.value.units.isEmpty || !$0.value.filed.isEmpty }, mine)
            if !mine.contains("\\n") { XCTAssertEqual(mine, s(r[1]), "written as the laptop writes it") }
        }
        for r in rows("merge") {
            let prev: SheetIndex.Entry? = r[0] == .null ? nil : SheetIndex.Entry(notes: SheetIndex.notesMap(r[0]["notes"]), units: strs(r[0]["units"]), filed: s(r[0]["filed"]) ?? "")
            let e = r[1]
            let got = SheetIndex.merge(prev, file: s(e["file"]) ?? "", notes: s(e["notes"]) ?? "", units: strs(e["units"]), filed: s(e["filed"]) ?? "")
            XCTAssertEqual(got, entry(r[2]), "\(r[0].text)")
        }
        for r in rows("notesText") { XCTAssertEqual(SheetIndex.notesText(SheetIndex.notesMap(r[0])), s(r[1]), r[0].text) }
    }

    // MARK: the phone and iPad's own

    func testIndexJoinsTheSheets() {
        let (root, m) = models[0]
        let key = StudySheets.relIn(root, m.sheets.first { $0.title == "Cumulative test" }!.path)
        let idx = [key: SheetIndex.Entry(notes: [("x.pdf", "Two pages missing")], units: ["R3.4"], filed: "2026-11-16")]
        let joined = StudySheets.withIndex(m, root: root, index: idx)
        let cum = joined.sheets.first { $0.title == "Cumulative test" }!
        XCTAssertEqual(cum.notes, "Two pages missing")
        XCTAssertEqual(cum.codeFrom["R3.4"], "upload")
        XCTAssertTrue(cum.search.contains("two pages missing"))
        XCTAssertEqual(StudySheets.sheetsFor(unit: "R3", in: joined.sheets).map(\.title), ["Cumulative test"])
    }

    func testAnswerFormatCarriesTheSchema() throws {
        let f = StudyUpload.answerFormat()
        XCTAssertTrue(f.contains("```json"))
        let json = try XCTUnwrap(f.range(of: "{\"type\"").map { String(f[$0.lowerBound...]) })
        XCTAssertNotNil(try? JSONValue.parse(json))
    }
}
