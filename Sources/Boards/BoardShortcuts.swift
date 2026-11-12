import UIKit
import PencilKit
import NexusCore

// The iPad's board keys and gestures (Settings › Shortcuts, "On a board"), kept apart from the board itself: the keys are the
// navigation controller's key commands (it is in the responder chain above the canvas), built from the keys in effect each time iPadOS
// asks, so an edit works at once and holding ⌘ lists them; the gestures are recognizers and a Pencil interaction added to the canvas,
// which look up the action bound to the gesture when it happens. Every action runs through BoardController.runShortcut(_:).

/// The board's navigation controller (BoardHost): its key commands and gestures.
final class BoardNavigationController: UINavigationController {
    private(set) var gestures: BoardGestures?

    var board: BoardController? { viewControllers.first as? BoardController }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if gestures == nil, let b = board { gestures = BoardGestures(board: b) }
    }

    override var keyCommands: [UIKeyCommand]? {
        // a sheet over the board (the text editor, a picker) keeps the keyboard to itself
        guard let b = board, presentedViewController == nil, b.presentedViewController == nil else { return [] }
        var out: [UIKeyCommand] = []
        for s in ShortcutCenter.shared.ipad.shortcuts where s.scope == "board" && s.kind == .key && b.canRunShortcut(s.id) {
            for k in s.keys {
                if let c = KeyMap.keyCommand(k, title: s.name, id: s.id, action: #selector(runKey(_:))) { out.append(c) }
            }
        }
        return out
    }

    @objc func runKey(_ c: UIKeyCommand) {
        if let id = c.propertyList as? String { board?.runShortcut(id) }
    }
}

extension BoardController {
    /// Whether a board shortcut can do anything now (a key that can't passes on to iPadOS).
    func canRunShortcut(_ id: String) -> Bool {
        switch id {
        case "board.close", "board.zoomIn", "board.zoomOut", "board.zoomReset": return true
        case "board.contents": return !pdfs.isEmpty
        case "board.edit": return !readOnly && selectedItem?.type == "text"
        case "board.delete", "board.deselect": return !readOnly && selected != nil
        default: return !readOnly
        }
    }

    /// Runs a board shortcut (a key or a gesture).
    func runShortcut(_ id: String) {
        guard canRunShortcut(id) else { return }
        switch id {
        case "board.close": close()
        case "board.undo", "gesture.undo": undo()
        case "board.redo", "gesture.redo": redo()
        case "board.zoomIn": zoomShortcut(by: 1.25)
        case "board.zoomOut": zoomShortcut(by: 0.8)
        case "board.zoomReset": zoomShortcut(by: nil)
        case "board.contents":
            showContents(from: bar.pagePill)
        case "board.fingers", "gesture.fingers":
            BoardTools.shared.fingersDraw.toggle()
            toolChanged()
            toast(BoardTools.shared.fingersDraw ? "Fingers draw too" : "Pencil only: fingers scroll and pick things")
        case "board.tools", "gesture.tools": toggleTools()
        case "board.pen": tools?.pen()
        case "board.eraser", "gesture.eraser": tools?.eraserAndBack()
        case "board.lasso": selectTool(.lasso)
        case "board.lastTool", "gesture.lastTool": tools?.last()
        case "board.addText": insertText()
        case "board.addImage": pickImage()
        case "board.addPdf": pickPdf()
        case "board.addRect": insertShape("rect")
        case "board.addEllipse": insertShape("ellipse")
        case "board.addLine": insertShape("line")
        case "board.addArrow": insertShape("arrow")
        case "board.edit": editSelected()
        case "board.delete": deleteSelected()
        case "board.deselect": selected = nil
        default: break
        }
    }

    var tools: BoardGestures? { (navigationController as? BoardNavigationController)?.gestures }

    /// Shows or hides the board's bars.
    func toggleTools() {
        setBarsHidden(!bar.isHidden)
    }

    /// Zoom about the middle of the screen; nil = actual size.
    func zoomShortcut(by factor: CGFloat?) {
        let mid = CGPoint(x: visibleBoard.midX, y: visibleBoard.midY)
        let z = factor.map { canvas.zoomScale * $0 } ?? 1
        canvas.zoomScale = min(max(z, canvas.minimumZoomScale), canvas.maximumZoomScale)
        updateContentSize()
        let nz = canvas.zoomScale
        scroll(toBoard: CGPoint(x: mid.x - canvas.bounds.width / 2 / nz, y: mid.y - canvas.bounds.height / 2 / nz))
        sharpenText()
        showSelection()
    }
}

/// A board's gestures (two- and three-finger taps, the Pencil's double-tap and squeeze) and its tool switches (eraser and back, the
/// last tool), for the actions Settings › Shortcuts puts on them. A two-finger double tap always shows everything on the board (the
/// zoom pill's "Show everything"); the two-finger tap waits for it to fail. While both Pencil gestures are left to iPadOS, PencilKit
/// does what Settings › Apple Pencil says; once one of them has a Nexus action, this board takes the Pencil's gestures and does
/// iPadOS's choice itself for the other. The board's quietCanvasMenus (BoardHoldMenu.swift) leaves these taps on.
final class BoardGestures: NSObject, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    weak var board: BoardController?
    let twoFingers = UITapGestureRecognizer()
    let threeFingers = UITapGestureRecognizer()
    let twoFingersTwice = UITapGestureRecognizer()
    let pencil = UIPencilInteraction()
    private var observer: NSObjectProtocol?
    private var turnedOff: [UIPencilInteraction] = []

    init(board: BoardController) {
        self.board = board
        super.init()
        twoFingersTwice.numberOfTapsRequired = 2
        for (g, n) in [(twoFingers, 2), (threeFingers, 3), (twoFingersTwice, 2)] {
            g.numberOfTouchesRequired = n
            g.allowedTouchTypes = BoardController.direct
            g.cancelsTouchesInView = false
            g.delegate = self
            g.addTarget(self, action: #selector(tapped(_:)))
            board.canvas.addGestureRecognizer(g)
        }
        twoFingers.require(toFail: twoFingersTwice)
        // a quick pinch is never a tap: a pinch read as a two-finger tap ran Undo (the Nov 12 crash came through this way)
        if let pinch = board.canvas.pinchGestureRecognizer {
            for g in [twoFingers, threeFingers, twoFingersTwice] { g.require(toFail: pinch) }
        }
        pencil.delegate = self
        board.canvas.addInteraction(pencil)
        observer = NotificationCenter.default.addObserver(forName: ShortcutCenter.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        if g === twoFingersTwice {
            if let b = board, b.presentedViewController == nil { b.showEverything() }
            return
        }
        run(g === twoFingers ? ShortcutRegistry.twoFingerTap : ShortcutRegistry.threeFingerTap)
    }

    /// Runs what the gesture is bound to now.
    func run(_ gesture: String) {
        guard let b = board, b.presentedViewController == nil, let id = ShortcutCenter.shared.action(forGesture: gesture) else { return }
        if id == ShortcutRegistry.systemPencil { systemAction(gesture); return }
        b.runShortcut(id)
    }

    // MARK: the Pencil

    /// Takes the Pencil's gestures only when one of them has a Nexus action (or is off); otherwise PencilKit's own handling stays.
    func refresh() {
        let mine = ShortcutRegistry.pencilGestures.contains { ShortcutCenter.shared.action(forGesture: $0) != ShortcutRegistry.systemPencil }
        pencil.isEnabled = mine
        if mine {
            guard let canvas = board?.canvas else { return }
            var views: [UIView] = []
            var v: UIView? = canvas
            while let x = v { views.append(x); v = x.superview }
            for view in views {
                for i in view.interactions {
                    if let p = i as? UIPencilInteraction, p !== pencil, p.isEnabled { p.isEnabled = false; turnedOff.append(p) }
                }
            }
        } else {
            for p in turnedOff { p.isEnabled = true }
            turnedOff = []
        }
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        run(ShortcutRegistry.pencilDoubleTap)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        run(ShortcutRegistry.pencilDoubleTap)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { run(ShortcutRegistry.pencilSqueeze) }
    }

    /// What Settings › Apple Pencil says for this gesture, done here (only while the board has taken the Pencil's gestures).
    func systemAction(_ gesture: String) {
        var action = UIPencilInteraction.preferredTapAction
        if gesture == ShortcutRegistry.pencilSqueeze {
            if #available(iOS 17.5, *) { action = UIPencilInteraction.preferredSqueezeAction } else { return }
        }
        switch action {
        case .ignore: break
        case .switchEraser: eraserAndBack()
        case .switchPrevious: last()
        default: board?.toggleTools()
        }
    }

    // MARK: tools (the board's bar keeps the tool, BoardTools)

    func pen() {
        board?.selectTool(.pen)
    }

    func eraserAndBack() {
        let t = BoardTools.shared
        if t.tool == .eraser { board?.selectTool(t.previousTool == .eraser ? .pen : t.previousTool) } else { board?.selectTool(.eraser) }
    }

    func last() {
        let t = BoardTools.shared
        board?.selectTool(t.previousTool == t.tool ? .pen : t.previousTool)
    }
}
