import UIKit
import NexusCore

/// The formatting row over the keyboard (at the bottom of the screen with a keyboard attached), in the laptop's text bar's order:
/// Style | Bold, Italic, Underline, Strike, Highlight, Code | Bullets, Numbers, Checklist, Link | Font, Size, Colour, Background |
/// … (the block's menu) and Done.
final class FormatBar: UIInputView {
    weak var session: WritingSession?
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var styleButton = UIButton(type: .system)
    private var countLabel = UILabel()
    /// á é í ó ú ñ ü ¿ ¡, shown for a Spanish block.
    private let accentStack = UIStackView()
    /// A solid backing: on iPadOS 26 a `.keyboard` input view draws nothing behind its buttons, so the board showed through.
    private let backdrop = UIView()
    private let hairline = UIView()

    init(session: WritingSession) {
        self.session = session
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 50), inputViewStyle: .keyboard)
        autoresizingMask = [.flexibleWidth]
        backdrop.backgroundColor = .secondarySystemBackground
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        addSubview(hairline)
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 50) }

    private func button(_ symbol: String, _ label: String, action: String? = nil, menu: UIMenu? = nil) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
        let b = UIButton(configuration: config)
        b.accessibilityLabel = label
        b.toolTip = label
        if let menu {
            b.menu = menu
            b.showsMenuAsPrimaryAction = true
        } else if let action {
            b.addAction(UIAction { [weak self] _ in self?.session?.perform(action) }, for: .touchUpInside)
        }
        return b
    }

    /// Link: the selection or the word at the caret, else it asks for the address (⌘K keeps typing `[]()`).
    private func linkButton() -> UIButton {
        let b = button("link", "Link")
        b.addAction(UIAction { [weak self] _ in self?.session?.linkFromBar() }, for: .touchUpInside)
        return b
    }

    private func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(v)
        NSLayoutConstraint.activate([
            wrap.widthAnchor.constraint(equalToConstant: 13),
            wrap.heightAnchor.constraint(equalToConstant: 30),
            v.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            v.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
    }

    private func buildAccents() {
        accentStack.axis = .horizontal
        accentStack.spacing = 0
        for ch in Accents.spanishRow {
            var c = UIButton.Configuration.plain()
            c.title = ch
            c.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7)
            c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a; a.font = UIFont.systemFont(ofSize: 18); return a
            }
            let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.session?.insert(ch) })
            b.accessibilityLabel = "Type \(ch)"
            accentStack.addArrangedSubview(b)
        }
        accentStack.isHidden = true
    }

    private func build() {
        buildAccents()
        var config = UIButton.Configuration.plain()
        config.title = "Body"
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        styleButton = UIButton(configuration: config)
        styleButton.showsMenuAsPrimaryAction = true
        styleButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.styleItems() ?? []) }])
        styleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        let views: [UIView] = [
            styleButton, divider(),
            button("bold", "Bold", action: "bold"),
            button("italic", "Italic", action: "italic"),
            button("underline", "Underline", action: "underline"),
            button("strikethrough", "Strikethrough", action: "strike"),
            button("highlighter", "Highlight", menu: highlightMenu()),
            button("chevron.left.forwardslash.chevron.right", "Code", action: "code"),
            divider(),
            button("list.bullet", "Bulleted list", action: "bullets"),
            button("list.number", "Numbered list", action: "numbers"),
            button("checklist", "Checklist", action: "checklist"),
            linkButton(),
            divider(),
            button("textformat", "Font", menu: deferred { [weak self] in self?.fontItems() ?? [] }),
            button("textformat.size", "Size", menu: deferred { [weak self] in self?.sizeItems() ?? [] }),
            button("paintpalette", "Colour", menu: colourMenu()),
            button("square.fill.on.square", "Background", menu: deferred { [weak self] in self?.fillItems() ?? [] }),
            divider(),
            button("globe", "Spanish", menu: deferred { [weak self] in
                guard let s = self?.session, let b = s.board else { return [] }
                return b.spanishMenu(s.id)
            }),
            accentStack,
            button("text.badge.checkmark", "Review", menu: deferred { [weak self] in self?.reviewItems() ?? [] }),
            button("square.on.square", "Drafts", menu: deferred { [weak self] in
                guard let s = self?.session, let b = s.board else { return [] }
                return b.draftMenu(s.id)
            }),
            button("ellipsis.circle", "More", menu: deferred { [weak self] in self?.moreItems() ?? [] }),
        ]
        for v in views { stack.addArrangedSubview(v) }
        countLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        countLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(countLabel)
        var doneConfig = UIButton.Configuration.plain()
        doneConfig.title = "Done"
        let done = UIButton(configuration: doneConfig)
        done.addAction(UIAction { [weak self] _ in self?.session?.perform("done") }, for: .touchUpInside)
        stack.addArrangedSubview(done)
    }

    private func deferred(_ items: @escaping () -> [UIMenuElement]) -> UIMenu {
        UIMenu(children: [UIDeferredMenuElement.uncached { done in done(items()) }])
    }

    /// Show where the caret is: its style, and the block's word count.
    func refresh() {
        guard let s = session else { return }
        var config = styleButton.configuration
        config?.title = s.currentStyle.label
        styleButton.configuration = config
        let c = LiveMarkdown.count(s.text)
        var label = c.words == 1 ? "1 word" : "\(c.words) words"
        if let it = s.item, let left = Practice.left(it) {
            label = (left > 0 ? "Practice \(Practice.clock(left)) left" : "Practice time's up") + " · " + label
            countLabel.textColor = left > 0 ? .secondaryLabel : .systemOrange
        } else {
            countLabel.textColor = .secondaryLabel
        }
        countLabel.text = label
        let spanish = s.isSpanish
        if accentStack.isHidden == spanish { accentStack.isHidden = !spanish }
    }

    // MARK: menus

    private func styleItems() -> [UIMenuElement] {
        guard let s = session else { return [] }
        let current = s.currentStyle
        let styles: [UIMenuElement] = BlockStyle.allCases.map { st in
            UIAction(title: st.label, state: st == current ? .on : .off) { [weak s] _ in s?.setStyle(st) }
        }
        let id = s.id
        return [UIMenu(options: .displayInline, children: styles),
                UIAction(title: "Edit styles and font…", image: UIImage(systemName: "slider.horizontal.3")) { [weak b = s.board] _ in
                    b?.openStyles(id, style: current)
                }]
    }

    private func swatch(_ c: UIColor) -> UIImage {
        let size = CGSize(width: 18, height: 18)
        return UIGraphicsImageRenderer(size: size).image { _ in
            c.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)).fill()
            UIColor(white: 0, alpha: 0.2).setStroke()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)).stroke()
        }.withRenderingMode(.alwaysOriginal)
    }

    private func highlightMenu() -> UIMenu {
        UIMenu(title: "Highlight", children: BlockLook.highlights.map { h in
            UIAction(title: h.label, image: swatch(h.color)) { [weak self] _ in self?.session?.highlight(h.key) }
        })
    }

    /// Text colour: for the selected words; "Whole block" sets the block's own colour.
    private func colourMenu() -> UIMenu {
        let words = BlockLook.textColors.dropFirst().map { c in
            UIAction(title: c.label, image: swatch(c.color)) { [weak self] _ in self?.session?.textColor(c.key) }
        }
        let block = UIMenu(title: "Whole block", children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.blockColourItems() ?? [])
        }])
        return UIMenu(title: "Text colour", children: [UIMenu(options: .displayInline, children: words), block])
    }

    private func blockColourItems() -> [UIMenuElement] {
        guard let s = session, let it = s.item else { return [] }
        let current = (TextLook.look(it).color ?? TextLook.colors[0].hex).uppercased()
        return TextLook.colors.enumerated().map { i, c in
            UIAction(title: c.label, image: swatch(BlockLook.hex(c.hex)), state: current == c.hex.uppercased() ? .on : .off) { [weak s] _ in
                s?.board?.setBlockLook(s?.id ?? "", "color", i == 0 ? nil : c.hex)
            }
        }
    }

    private func fontItems() -> [UIMenuElement] {
        guard let s = session else { return [] }
        return BlockLook.families.map { f in
            UIAction(title: f.label, state: s.look.family == f.key ? .on : .off) { [weak s] _ in
                s?.board?.setBlockField(s?.id ?? "", "font", f.key == "sans" ? nil : .string(f.key))
            }
        }
    }

    private func sizeItems() -> [UIMenuElement] {
        guard let s = session, let it = s.item else { return [] }
        let current = TextLook.look(it).size ?? TextLook.defaultSize
        return TextLook.sizes.map { z in
            UIAction(title: z.label, state: current == z.px ? .on : .off) { [weak s] _ in
                s?.board?.setBlockLook(s?.id ?? "", "size", String(z.px))
            }
        }
    }

    private func fillItems() -> [UIMenuElement] {
        guard let s = session, let it = s.item else { return [] }
        let current = (TextLook.look(it).fill ?? "").uppercased()
        return TextLook.fills.map { f in
            UIAction(title: f.label, image: f.hex.isEmpty ? UIImage(systemName: "circle.slash") : swatch(BlockLook.hex(f.hex)),
                     state: current == f.hex.uppercased() ? .on : .off) { [weak s] _ in
                s?.board?.setBlockLook(s?.id ?? "", "fill", f.hex.isEmpty ? nil : f.hex)
            }
        }
    }

    private func reviewItems() -> [UIMenuElement] {
        guard let s = session, let b = s.board, let it = s.item else { return [] }
        let id = s.id
        let on = it.json["review"]?.bool ?? false
        let n = s.suggestions.count
        var out: [UIMenuElement] = [
            UIAction(title: "Review mode", subtitle: on ? "Typing suggests changes" : "Typing changes the words", image: UIImage(systemName: "pencil.and.list.clipboard"),
                     state: on ? .on : .off) { [weak b] _ in b?.setBlockField(id, "review", on ? nil : .bool(true)) },
            UIAction(title: n == 1 ? "1 suggestion" : "\(n) suggestions", attributes: .disabled) { _ in },
        ]
        guard n > 0 else { return out }
        out.append(UIMenu(options: .displayInline, children: [
            UIAction(title: "Next suggestion", image: UIImage(systemName: "arrow.down.circle")) { [weak s] _ in s?.nextSuggestion() },
            UIAction(title: "Accept", image: UIImage(systemName: "checkmark")) { [weak s] _ in s?.acceptHere(true) },
            UIAction(title: "Reject", image: UIImage(systemName: "xmark")) { [weak s] _ in s?.acceptHere(false) },
        ]))
        out.append(UIMenu(options: .displayInline, children: [
            UIAction(title: "Accept all", image: UIImage(systemName: "checkmark.circle")) { [weak s] _ in s?.reviewAll(true) },
            UIAction(title: "Reject all", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak s] _ in s?.reviewAll(false) },
        ]))
        return out
    }

    private func moreItems() -> [UIMenuElement] {
        guard let s = session, let b = s.board, let it = s.item else { return [] }
        let id = s.id
        let c = LiveMarkdown.count(s.text)
        var out: [UIMenuElement] = []
        out.append(UIAction(title: "Writing view", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { [weak b] _ in b?.openWritingView(id) })
        out.append(UIAction(title: "Find and replace", image: UIImage(systemName: "magnifyingglass")) { [weak b] _ in b?.openFind(id) })
        out.append(UIAction(title: "\(c.words) words · \(c.characters) characters", attributes: .disabled) { _ in })
        let sel = s.textView.selectedRange
        let shown = b.marksShown
        out.append(UIMenu(options: .displayInline, children: [
            UIAction(title: "Comment", image: UIImage(systemName: "text.bubble")) { [weak b] _ in b?.addComment(on: id, range: sel) },
            UIAction(title: "Add a Nexus task", image: UIImage(systemName: "checkmark.circle.badge.plus")) { [weak b] _ in b?.addNexusTask(from: id, range: sel) },
            UIAction(title: "All comments", image: UIImage(systemName: "list.bullet.rectangle")) { [weak b] _ in b?.openComments() },
            UIAction(title: "Show comments", image: UIImage(systemName: "eye"), state: shown ? .on : .off) { [weak b] _ in b?.marksShown = !shown },
        ]))
        out.append(UIAction(title: "Cover with revision tape", subtitle: "A strip on each line; tap one to peek", image: UIImage(systemName: "rectangle.dashed")) { [weak b] _ in
            b?.endWriting()
            b?.tapeBlock(id)
        })
        if it.json["chip"]?.bool == true {
            out.append(UIAction(title: "Unfold", subtitle: "Show the words on the board again", image: UIImage(systemName: "rectangle.expand.vertical")) { [weak b] _ in
                b?.setBlockField(id, "chip", nil)
            })
        } else {
            out.append(UIAction(title: "Fold into a chip", image: UIImage(systemName: "rectangle.compress.vertical")) { [weak b] _ in
                b?.endWriting()
                b?.setBlockField(id, "chip", .bool(true))
            })
        }
        let push = it.json["push"]?.bool ?? false
        out.append(UIMenu(options: .displayInline, children: [
            UIAction(title: "Make room", image: UIImage(systemName: "arrow.down.to.line")) { [weak b] _ in b?.makeRoom(id) },
            UIAction(title: "Push things below", image: UIImage(systemName: "arrow.down.square"), state: push ? .on : .off) { [weak b] _ in
                b?.setBlockField(id, "push", push ? nil : .bool(true))
            },
        ]))
        let chem = it.json["chem"]?.bool ?? true
        out.append(UIAction(title: "Chemistry subscripts", image: UIImage(systemName: "flask"), state: chem ? .on : .off) { [weak b] _ in
            b?.setBlockField(id, "chem", chem ? .bool(false) : nil)
        })
        out.append(UIMenu(options: .displayInline, children: [
            UIAction(title: "Delete block", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak b] _ in b?.deleteBlock(id) },
        ]))
        return out
    }
}
