import XCTest
@testable import NexusCore

/// The shortcuts files (docs/data-format.md "Shortcuts"): reading the laptop's, writing the iPad's, the one-line keys edit, key names
/// and the conflict rules.
final class ShortcutsTests: XCTestCase {
    /// The contract's example, as the laptop writes it (comments, a flow-map entry, a hold key).
    let laptop = """
    # Nexus's shortcuts on the laptop. Change them in Settings › Shortcuts (on the laptop or the iPad), or edit `keys` here.
    format: nexus-shortcuts/1
    device: laptop
    scopes:                         # where shortcuts work; `in:` is the scope it sits inside
      - { id: system, name: Across Windows }
      - { id: app, name: Everywhere in Nexus }
      - { id: note, name: In a note, in: app }
      - { id: card, name: On a task card, in: app }
      - { id: calendar, name: In the calendar, in: app }
    shortcuts:
      - id: app.switcher            # stable, never shown; a renamed command keeps its id
        name: Open quick switcher
        group: Find and open        # the collapsible section on the Shortcuts screen
        scope: app
        keys: ["Ctrl+O"]            # 0..n bindings, JSON-style quoted strings; [] = off
        default: ["Ctrl+O"]
      - { id: sys.dictation, name: Dictation (hold), group: Across Windows, scope: system, kind: hold, keys: ["Ctrl+Win"], default: ["Ctrl+Win"] }
      - id: note.find
        name: Find in the note
        group: Notes
        scope: note
        keys: ["Ctrl+F"]
        default: ["Ctrl+F"]
      - id: app.find
        name: Search everything
        group: Find and open
        scope: app
        keys: ["Ctrl+F", "Ctrl+Shift+F"]
        default: ["Ctrl+Shift+F"]
      - id: card.done
        name: Tick the card
        group: Tasks
        scope: card
        keys: ["X"]
        default: ["X"]
      - id: cal.next
        name: Next week
        group: Calendar
        scope: calendar
        keys: ["X"]
        default: ["N"]
      - id: tabs.split
        name: Split right
        group: Tabs
        scope: app
        keys: ["Ctrl+\\\\"]
        default: ["Ctrl+\\\\"]

    """

    func testReadsTheLaptopsFile() throws {
        let f = try ShortcutsYaml.parse(laptop)
        XCTAssertEqual(f.device, "laptop")
        XCTAssertEqual(f.scopes.map(\.id), ["system", "app", "note", "card", "calendar"])
        XCTAssertEqual(f.scope("note")?.parent, "app")
        XCTAssertEqual(f.ancestors(of: "note"), ["app"])
        XCTAssertEqual(f["app.switcher"]?.keys, ["Ctrl+O"])
        XCTAssertEqual(f["app.switcher"]?.group, "Find and open")
        let d = try XCTUnwrap(f["sys.dictation"])
        XCTAssertEqual(d.kind, .hold)
        XCTAssertEqual(d.scope, "system")
        XCTAssertEqual(d.keys, ["Ctrl+Win"])
        XCTAssertEqual(f["tabs.split"]?.keys, ["Ctrl+\\"])
        XCTAssertTrue(f["cal.next"]!.isOverridden)
        XCTAssertFalse(f["card.done"]!.isOverridden)
        XCTAssertEqual(f.groups, ["Find and open", "Across Windows", "Notes", "Tasks", "Calendar", "Tabs"])
    }

    func testANewerOrBrokenFileIsRefused() {
        XCTAssertThrowsError(try ShortcutsYaml.parse("format: nexus-shortcuts/2\ndevice: laptop\nshortcuts: []\n")) { e in
            XCTAssertEqual(e as? ShortcutsYaml.Failure, .newer("nexus-shortcuts/2"))
        }
        XCTAssertThrowsError(try ShortcutsYaml.parse("format: nexus-shortcuts/1\nshortcuts:\n  - id: x\n   name: bad\n  - [\n"))
        XCTAssertThrowsError(try ShortcutsYaml.parse("device: laptop\n"))
    }

    // MARK: the line edit of keys

    func testChangesOnlyTheKeysLineOfABlockShortcut() throws {
        let out = try ShortcutsYaml.setKeys(laptop, id: "app.switcher", keys: ["Ctrl+P", "Ctrl+Alt+O"])
        let before = laptop.components(separatedBy: "\n"), after = out.components(separatedBy: "\n")
        XCTAssertEqual(before.count, after.count)
        let changed = zip(before, after).filter { $0 != $1 }
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first?.1, "    keys: [\"Ctrl+P\", \"Ctrl+Alt+O\"]            # 0..n bindings, JSON-style quoted strings; [] = off")
        XCTAssertEqual(try ShortcutsYaml.parse(out)["app.switcher"]?.keys, ["Ctrl+P", "Ctrl+Alt+O"])
    }

    func testChangesTheKeysOfAFlowMapShortcut() throws {
        let out = try ShortcutsYaml.setKeys(laptop, id: "sys.dictation", keys: ["Ctrl+Alt+Win"])
        let line = out.components(separatedBy: "\n").first { $0.contains("sys.dictation") }
        XCTAssertEqual(line, "  - { id: sys.dictation, name: Dictation (hold), group: Across Windows, scope: system, kind: hold, keys: [\"Ctrl+Alt+Win\"], default: [\"Ctrl+Win\"] }")
        XCTAssertEqual(try ShortcutsYaml.parse(out)["sys.dictation"]?.keys, ["Ctrl+Alt+Win"])
        // turned off
        let off = try ShortcutsYaml.setKeys(out, id: "sys.dictation", keys: [])
        XCTAssertEqual(try ShortcutsYaml.parse(off)["sys.dictation"]?.keys, [])
    }

    func testKeysWithBracketsAndBackslashesSurvive() throws {
        let out = try ShortcutsYaml.setKeys(laptop, id: "tabs.split", keys: ["Ctrl+]", "Ctrl+\\"])
        XCTAssertEqual(try ShortcutsYaml.parse(out)["tabs.split"]?.keys, ["Ctrl+]", "Ctrl+\\"])
        let again = try ShortcutsYaml.setKeys(out, id: "tabs.split", keys: ["Ctrl+["])
        XCTAssertEqual(try ShortcutsYaml.parse(again)["tabs.split"]?.keys, ["Ctrl+["])
    }

    func testAMissingKeysLineGoesBeforeDefault() throws {
        let text = "format: nexus-shortcuts/1\ndevice: laptop\nshortcuts:\n  - id: a\n    name: A\n    scope: app\n    default: [\"Ctrl+A\"]\n  - { id: b, name: B, default: [\"Ctrl+B\"] }\n"
        let out = try ShortcutsYaml.setKeys(text, id: "a", keys: ["Ctrl+Q"])
        XCTAssertTrue(out.contains("    scope: app\n    keys: [\"Ctrl+Q\"]\n    default: [\"Ctrl+A\"]\n"))
        let out2 = try ShortcutsYaml.setKeys(out, id: "b", keys: ["Ctrl+R"])
        XCTAssertTrue(out2.contains("  - { id: b, name: B, keys: [\"Ctrl+R\"], default: [\"Ctrl+B\"] }"))
        let f = try ShortcutsYaml.parse(out2)
        XCTAssertEqual(f["a"]?.keys, ["Ctrl+Q"])
        XCTAssertEqual(f["b"]?.keys, ["Ctrl+R"])
    }

    func testAnUnknownIdIsNotWritten() {
        XCTAssertThrowsError(try ShortcutsYaml.setKeys(laptop, id: "nope", keys: ["Ctrl+Q"])) { e in
            XCTAssertEqual(e as? ShortcutsYaml.Failure, .notFound("nope"))
        }
    }

    // MARK: the iPad's own file

    let scopes = [ShortcutScope(id: "app", name: "Everywhere in Nexus"), ShortcutScope(id: "board", name: "On a board", parent: "app")]
    var registry: [Shortcut] {
        [Shortcut(id: "app.today", name: "Go to Today", group: "Go to", scope: "app", defaults: ["Cmd+1"]),
         Shortcut(id: "app.settings", name: "Open Settings", group: "Go to", scope: "app", defaults: ["Cmd+,"]),
         Shortcut(id: "app.undo", name: "Undo: the last change", group: "Tasks", scope: "app", defaults: ["Cmd+Z"]),
         Shortcut(id: "board.undo", name: "Undo", group: "Board", scope: "board", defaults: ["Cmd+Z"]),
         Shortcut(id: "gesture.undo", name: "Undo", group: "Gestures", scope: "board", kind: .gesture, defaults: ["Two-finger tap"]),
         Shortcut(id: "gesture.redo", name: "Redo", group: "Gestures", scope: "board", kind: .gesture, defaults: ["Three-finger tap"])]
    }

    func testWritesTheWholeFileAndReadsItBack() throws {
        var f = ShortcutFile.merged(device: "ipad", scopes: scopes, registry: registry, existing: nil)
        f.setKeys("app.today", ["Cmd+Shift+1"])
        let text = ShortcutsYaml.write(f)
        XCTAssertTrue(text.hasPrefix("# Nexus's shortcuts on the iPad."))
        XCTAssertTrue(text.contains("\nformat: nexus-shortcuts/1\ndevice: ipad\nscopes:\n  - { id: app, name: Everywhere in Nexus }\n  - { id: board, name: On a board, in: app }\n"))
        XCTAssertTrue(text.contains("  - id: app.today\n    name: Go to Today\n    group: Go to\n    scope: app\n    keys: [\"Cmd+Shift+1\"]\n    default: [\"Cmd+1\"]\n"))
        XCTAssertTrue(text.contains("    name: 'Undo: the last change'\n"))
        XCTAssertTrue(text.contains("    scope: board\n    kind: gesture\n    keys: [\"Two-finger tap\"]\n"))
        XCTAssertEqual(try ShortcutsYaml.parse(text), f)
        // the laptop's one-line edit of the iPad's file reads back the same
        let edited = try ShortcutsYaml.setKeys(text, id: "app.settings", keys: ["Cmd+;"])
        XCTAssertEqual(try ShortcutsYaml.parse(edited)["app.settings"]?.keys, ["Cmd+;"])
    }

    func testMergeKeepsChangesAndFollowsANewDefault() throws {
        var old = ShortcutFile.merged(device: "ipad", scopes: scopes, registry: registry, existing: nil)
        old.setKeys("app.today", ["Cmd+T"])
        old.shortcuts.append(Shortcut(id: "gone", name: "Gone", group: "X", scope: "app", defaults: ["Cmd+G"]))
        var next = registry
        next[1].defaults = ["Cmd+;"]   // app.settings' default changed in an update
        next[0].defaults = ["Cmd+0"]   // so did app.today's, but it was changed by hand
        let f = ShortcutFile.merged(device: "ipad", scopes: scopes, registry: next, existing: old)
        XCTAssertEqual(f["app.settings"]?.keys, ["Cmd+;"])
        XCTAssertEqual(f["app.today"]?.keys, ["Cmd+T"])
        XCTAssertEqual(f["app.today"]?.defaults, ["Cmd+0"])
        XCTAssertNil(f["gone"])
    }

    // MARK: key names

    func testNormalisesKeys() {
        XCTAssertEqual(ShortcutKeys.normalize("shift+cmd+z", device: "ipad"), "Cmd+Shift+Z")
        XCTAssertEqual(ShortcutKeys.normalize("⌥⌘".map(String.init).joined(separator: "+") + "+1", device: "ipad"), "Cmd+Alt+1")
        XCTAssertEqual(ShortcutKeys.normalize("Option+Control+Command+return", device: "ipad"), "Cmd+Ctrl+Alt+Enter")
        XCTAssertEqual(ShortcutKeys.normalize("win+shift+s", device: "laptop"), "Shift+Win+S")
        XCTAssertEqual(ShortcutKeys.normalize("alt+ctrl+delete", device: "laptop"), "Ctrl+Alt+Delete")
        XCTAssertEqual(ShortcutKeys.normalize("ctrl+k ctrl+\\", device: "laptop"), "Ctrl+K Ctrl+\\")
        XCTAssertEqual(ShortcutKeys.normalize("Ctrl+Win", device: "laptop"), "Ctrl+Win")
        XCTAssertEqual(ShortcutKeys.normalize("f5", device: "laptop"), "F5")
        XCTAssertEqual(ShortcutKeys.normalize("Ctrl+escape", device: "laptop"), "Ctrl+Esc")
        XCTAssertEqual(ShortcutKeys.make(mods: ["Shift", "Cmd"], key: "K", device: "ipad"), "Cmd+Shift+K")
        XCTAssertEqual(ShortcutKeys.display("Cmd+Shift+Z", device: "ipad"), "⇧⌘Z")
        XCTAssertEqual(ShortcutKeys.display("Cmd+Ctrl+S", device: "ipad"), "⌃⌘S")
        XCTAssertEqual(ShortcutKeys.display("Backspace", device: "ipad"), "⌫")
        XCTAssertEqual(ShortcutKeys.display("ctrl+o", device: "laptop"), "Ctrl+O")
    }

    // MARK: conflicts

    func testConflictRulesOnTheLaptop() throws {
        var f = try ShortcutsYaml.parse(laptop)
        var issues = ShortcutConflicts.compute(f)
        // note sits inside app: the note's Ctrl+F takes over there, not an error
        XCTAssertEqual(issues["note.find"], [ShortcutIssue(kind: .takesOver, binding: "Ctrl+F", other: "app.find", scope: "note")])
        XCTAssertEqual(issues["app.find"], [ShortcutIssue(kind: .takenOver, binding: "Ctrl+F", other: "note.find", scope: "note")])
        // card and calendar sit side by side: never clash
        XCTAssertNil(issues["card.done"])
        XCTAssertNil(issues["cal.next"])
        XCTAssertEqual(ShortcutConflicts.errorCount(issues), 0)

        // the same binding twice in one scope: red on both rows
        f.setKeys("app.find", ["Ctrl+O"])
        issues = ShortcutConflicts.compute(f)
        XCTAssertEqual(issues["app.switcher"], [ShortcutIssue(kind: .conflict, binding: "Ctrl+O", other: "app.find")])
        XCTAssertEqual(issues["app.find"], [ShortcutIssue(kind: .conflict, binding: "Ctrl+O", other: "app.switcher")])
        XCTAssertEqual(ShortcutConflicts.errorCount(issues), 2)

        // Windows' own keys clash with a system shortcut, not with an app one
        f.setKeys("sys.dictation", ["Win+L"])
        f.setKeys("app.find", ["alt+f4"])
        issues = ShortcutConflicts.compute(f)
        XCTAssertEqual(issues["sys.dictation"], [ShortcutIssue(kind: .reserved, binding: "Win+L")])
        XCTAssertNil(issues["app.find"])

        // a system binding shadows the same binding in every other scope (a warning)
        f.setKeys("sys.dictation", ["Ctrl+O"])
        issues = ShortcutConflicts.compute(f)
        XCTAssertEqual(issues["app.switcher"], [ShortcutIssue(kind: .shadowed, binding: "Ctrl+O", other: "sys.dictation")])
        XCTAssertNil(issues["sys.dictation"])
        XCTAssertEqual(ShortcutConflicts.errorCount(issues), 0)
    }

    func testConflictRulesOnTheIPad() {
        var f = ShortcutFile.merged(device: "ipad", scopes: scopes, registry: registry, existing: nil)
        var issues = ShortcutConflicts.compute(f)
        XCTAssertEqual(issues["board.undo"], [ShortcutIssue(kind: .takesOver, binding: "Cmd+Z", other: "app.undo", scope: "board")])
        XCTAssertEqual(issues["app.undo"], [ShortcutIssue(kind: .takenOver, binding: "Cmd+Z", other: "board.undo", scope: "board")])
        XCTAssertEqual(ShortcutConflicts.errorCount(issues), 0)

        // iPadOS keeps Cmd+Tab, Cmd+Space, Cmd+H and the Globe keys in every scope
        f.setKeys("app.today", ["Cmd+H"])
        f.setKeys("board.undo", ["Globe+Z", "cmd+space"])
        issues = ShortcutConflicts.compute(f)
        XCTAssertEqual(issues["app.today"], [ShortcutIssue(kind: .reserved, binding: "Cmd+H")])
        XCTAssertEqual(issues["board.undo"]?.map(\.kind), [.reserved, .reserved])

        // a gesture conflicts only with the same gesture (never with a key)
        f.setKeys("gesture.redo", ["Two-finger tap"])
        f.setKeys("app.today", ["Two-finger tap"])
        issues = ShortcutConflicts.compute(f)
        XCTAssertEqual(issues["gesture.undo"], [ShortcutIssue(kind: .conflict, binding: "Two-finger tap", other: "gesture.redo")])
        XCTAssertEqual(issues["gesture.redo"], [ShortcutIssue(kind: .conflict, binding: "Two-finger tap", other: "gesture.undo")])
        XCTAssertNil(issues["app.today"])
    }

    func testSwapAndReplace() {
        var f = ShortcutFile.merged(device: "ipad", scopes: scopes, registry: registry, existing: nil)
        XCTAssertEqual(ShortcutConflicts.holders(f, binding: "cmd+1", scope: "app", kind: .key, except: "app.settings").map(\.id), ["app.today"])
        XCTAssertEqual(ShortcutConflicts.holders(f, binding: "Cmd+1", scope: "board", kind: .key, except: "board.undo").map(\.id), [])
        // swap: Settings takes Cmd+1, Today gets Settings' old Cmd+,
        var swapped = f
        ShortcutConflicts.move(&swapped, binding: "Cmd+1", to: "app.settings", replacing: "Cmd+,", from: ["app.today"], swap: true)
        XCTAssertEqual(swapped["app.settings"]?.keys, ["Cmd+1"])
        XCTAssertEqual(swapped["app.today"]?.keys, ["Cmd+,"])
        // replace: Today loses it
        ShortcutConflicts.move(&f, binding: "Cmd+1", to: "app.settings", replacing: "Cmd+,", from: ["app.today"], swap: false)
        XCTAssertEqual(f["app.settings"]?.keys, ["Cmd+1"])
        XCTAssertEqual(f["app.today"]?.keys, [])
        // a gesture moves the same way
        ShortcutConflicts.move(&f, binding: "Two-finger tap", to: "gesture.redo", replacing: "Three-finger tap", from: ["gesture.undo"], swap: true)
        XCTAssertEqual(f["gesture.redo"]?.keys, ["Two-finger tap"])
        XCTAssertEqual(f["gesture.undo"]?.keys, ["Three-finger tap"])
    }

    func testTheFingerprintSeesAShortcutsEdit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-shortcuts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("shortcuts"), withIntermediateDirectories: true)
        try "nexus: 2\n".write(to: root.appendingPathComponent("nexus.yaml"), atomically: true, encoding: .utf8)
        let file = root.appendingPathComponent(DataFolder.shortcutsFile("ipad"))
        try "format: nexus-shortcuts/1\n".write(to: file, atomically: true, encoding: .utf8)
        let before = DataFolder.fingerprint(root)
        try "format: nexus-shortcuts/1\ndevice: ipad\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(before, DataFolder.fingerprint(root))
        XCTAssertEqual(DataFolder.load(root).groups.map(\.id), [])
    }
}
