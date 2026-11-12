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

    static func key(_ id: String, _ name: String, _ group: String, _ keys: [String]) -> Shortcut {
        Shortcut(id: id, name: name, group: group, scope: "app", defaults: keys)
    }

    static func onBoard(_ id: String, _ name: String, _ group: String, _ keys: [String]) -> Shortcut {
        Shortcut(id: id, name: name, group: group, scope: "board", defaults: keys)
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

        onBoard("board.close", "Close the board", "Board", ["Cmd+W"]),
        onBoard("board.undo", "Undo", "Board", ["Cmd+Z"]),
        onBoard("board.redo", "Redo", "Board", ["Cmd+Shift+Z"]),
        onBoard("board.zoomIn", "Zoom in", "Board", ["Cmd+="]),
        onBoard("board.zoomOut", "Zoom out", "Board", ["Cmd+-"]),
        onBoard("board.zoomReset", "Actual size", "Board", ["Cmd+0"]),
        onBoard("board.contents", "PDF contents", "Board", ["Cmd+G"]),
        onBoard("board.fingers", "Fingers draw too, or only scroll", "Board", ["Cmd+Shift+P"]),
        onBoard("board.tools", "Show or hide the tools", "Board", []),

        onBoard("board.pen", "Pen", "Board tools", ["P"]),
        onBoard("board.eraser", "Eraser, and back", "Board tools", ["E"]),
        onBoard("board.lasso", "Lasso", "Board tools", ["L"]),
        onBoard("board.lastTool", "Last tool", "Board tools", []),
        onBoard("board.addText", "Add text", "Board tools", ["T"]),
        onBoard("board.addImage", "Add an image…", "Board tools", []),
        onBoard("board.addPdf", "Add a PDF printout…", "Board tools", []),
        onBoard("board.addRect", "Add a rectangle", "Board tools", []),
        onBoard("board.addEllipse", "Add an ellipse", "Board tools", []),
        onBoard("board.addLine", "Add a line", "Board tools", []),
        onBoard("board.addArrow", "Add an arrow", "Board tools", []),
        onBoard("board.edit", "Edit the picked text", "Board tools", ["Enter"]),
        onBoard("board.delete", "Delete the picked item", "Board tools", ["Backspace"]),
        onBoard("board.deselect", "Let go of the picked item", "Board tools", ["Esc"]),

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
