import Foundation
import NexusCore

/// Every shortcut the iPad has: its stable id (written in `shortcuts/ipad.yaml`, never shown), name, section, where it works and its
/// default. The order here is the order on Settings › Shortcuts and in the file. Keys mirror the laptop's where that makes sense
/// (the places by number, N for a new task, Ctrl+F to search), with ⌘ for Ctrl.
enum ShortcutRegistry {
    static let device = "ipad"

    static let scopes = [
        ShortcutScope(id: "app", name: "Everywhere in Nexus"),
        ShortcutScope(id: "board", name: "On a board", parent: "app"),
    ]

    /// The gestures a board knows (the names `keys:` holds for a gesture).
    static let twoFingerTap = "Two-finger tap"
    static let threeFingerTap = "Three-finger tap"
    static let pencilDoubleTap = "Pencil double-tap"
    static let pencilSqueeze = "Pencil squeeze"
    static let gestures = [twoFingerTap, threeFingerTap, pencilDoubleTap, pencilSqueeze]
    static let pencilGestures = [pencilDoubleTap, pencilSqueeze]

    /// The gesture row that leaves the Pencil to what Settings › Apple Pencil on the iPad says.
    static let systemPencil = "gesture.ios"

    static func key(_ id: String, _ name: String, _ group: String, _ scope: String = "app", _ keys: [String]) -> Shortcut {
        Shortcut(id: id, name: name, group: group, scope: scope, defaults: keys)
    }

    static func gesture(_ id: String, _ name: String, _ keys: [String]) -> Shortcut {
        Shortcut(id: id, name: name, group: "Gestures", scope: "board", kind: .gesture, defaults: keys)
    }

    static let all: [Shortcut] = [
        key("app.today", "Go to Today", "Go to", ["Cmd+1"]),
        key("app.planner", "Go to Planner", "Go to", ["Cmd+2"]),
        key("app.tasks", "Go to Tasks", "Go to", ["Cmd+3"]),
        key("app.notebooks", "Go to Notebooks (Search boards)", "Go to", ["Cmd+4"]),
        key("app.inbox", "Go to Inbox", "Go to", ["Cmd+5"]),
        key("app.someday", "Go to Someday", "Go to", ["Cmd+6"]),
        key("app.settings", "Open Settings", "Go to", ["Cmd+,"]),
        key("app.sidebar", "Show or hide the sidebar", "Go to", ["Cmd+Ctrl+S"]),

        key("app.newTask", "New task", "Add and find", ["Cmd+N"]),
        key("app.search", "Search tasks", "Add and find", ["Cmd+F"]),
        key("app.newNotebook", "New notebook", "Add and find", ["Cmd+Shift+N"]),
        key("app.undo", "Undo the last change (the undo bar)", "Add and find", ["Cmd+Z"]),

        key("board.close", "Close the board", "Board", "board", ["Cmd+W"]),
        key("board.undo", "Undo", "Board", "board", ["Cmd+Z"]),
        key("board.redo", "Redo", "Board", "board", ["Cmd+Shift+Z"]),
        key("board.zoomIn", "Zoom in", "Board", "board", ["Cmd+="]),
        key("board.zoomOut", "Zoom out", "Board", "board", ["Cmd+-"]),
        key("board.zoomReset", "Actual size", "Board", "board", ["Cmd+0"]),
        key("board.contents", "PDF contents", "Board", "board", ["Cmd+G"]),
        key("board.fingers", "Fingers draw too, or only scroll", "Board", "board", ["Cmd+Shift+P"]),
        key("board.tools", "Show or hide the tools", "Board", "board", []),

        key("board.pen", "Pen", "Board tools", "board", ["P"]),
        key("board.eraser", "Eraser, and back", "Board tools", "board", ["E"]),
        key("board.lasso", "Lasso", "Board tools", "board", ["L"]),
        key("board.lastTool", "Last tool", "Board tools", "board", []),
        key("board.addText", "Add text", "Board tools", "board", ["T"]),
        key("board.addImage", "Add an image…", "Board tools", "board", []),
        key("board.addPdf", "Add a PDF printout…", "Board tools", "board", []),
        key("board.addRect", "Add a rectangle", "Board tools", "board", []),
        key("board.addEllipse", "Add an ellipse", "Board tools", "board", []),
        key("board.addLine", "Add a line", "Board tools", "board", []),
        key("board.addArrow", "Add an arrow", "Board tools", "board", []),
        key("board.edit", "Edit the picked text", "Board tools", "board", ["Enter"]),
        key("board.delete", "Delete the picked item", "Board tools", "board", ["Backspace"]),
        key("board.deselect", "Let go of the picked item", "Board tools", "board", ["Esc"]),

        gesture(systemPencil, "What iPadOS says (Settings › Apple Pencil)", [pencilDoubleTap, pencilSqueeze]),
        gesture("gesture.undo", "Undo", [twoFingerTap]),
        gesture("gesture.redo", "Redo", [threeFingerTap]),
        gesture("gesture.eraser", "Eraser, and back", []),
        gesture("gesture.lastTool", "Last tool", []),
        gesture("gesture.tools", "Show or hide the tools", []),
        gesture("gesture.fingers", "Fingers draw too, or only scroll", []),
    ]

    /// The gestures a row may pick (the iPadOS row only has the Pencil's).
    static func choices(for id: String) -> [String] { id == systemPencil ? pencilGestures : gestures }

    static var defaultFile: ShortcutFile { ShortcutFile.merged(device: device, scopes: scopes, registry: all, existing: nil) }
}
