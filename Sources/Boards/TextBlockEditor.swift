import SwiftUI
import UIKit
import NexusCore

/// Editing one typed block: its markdown, and its look (size, text color, background) as the laptop's text bar sets them
/// (renderer/src/app/boardtext.js: the first color, black, and no background take the key off, so a plain block stays plain).
/// It dismisses itself on Done, Cancel and Delete; Done hands back the markdown and the item with its new look.
struct TextBlockEditor: View {
    let onDone: (String, BoardItem) -> Void
    let onDelete: () -> Void

    private let original: String
    private let originalItem: BoardItem
    @State private var markdown: String
    @State private var item: BoardItem
    @State private var confirmDelete: Bool = false
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    init(markdown: String, item: BoardItem, onDone: @escaping (String, BoardItem) -> Void, onDelete: @escaping () -> Void) {
        self.onDone = onDone
        self.onDelete = onDelete
        self.original = markdown
        self.originalItem = item
        _markdown = State(initialValue: markdown)
        _item = State(initialValue: item)
    }

    private var changed: Bool { markdown != original || item != originalItem }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $markdown)
                    .font(.system(size: 16, design: .monospaced))
                    .focused($typing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 160)
                Divider()
                lookControls
                    .padding(16)
                Divider()
                preview
            }
            .navigationTitle("Text block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(markdown, item)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this block?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete block", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("Its words are deleted from the board too.")
            }
        }
        .interactiveDismissDisabled(changed)
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            typing = true
        }
    }

    // MARK: the look

    private var look: (size: Double?, color: String?, fill: String?) { TextLook.look(item) }

    private var lookControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Size").frame(width: 92, alignment: .leading).foregroundStyle(.secondary)
                Picker("Size", selection: sizeBinding) {
                    ForEach(0..<TextLook.sizes.count, id: \.self) { (i: Int) in
                        Text(TextLook.sizes[i].label).tag(TextLook.sizes[i].px)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Text("Text color").frame(width: 92, alignment: .leading).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(0..<TextLook.colors.count, id: \.self) { (i: Int) in
                        let c = TextLook.colors[i]
                        swatch(hex: c.hex, label: c.label, selected: currentColor == c.hex.uppercased()) {
                            item = TextLook.with(item, "color", i == 0 ? nil : c.hex)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Text("Background").frame(width: 92, alignment: .leading).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(0..<TextLook.fills.count, id: \.self) { (i: Int) in
                        let f = TextLook.fills[i]
                        swatch(hex: f.hex, label: f.label, selected: currentFill == f.hex.uppercased()) {
                            item = TextLook.with(item, "fill", f.hex.isEmpty ? nil : f.hex)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete block", systemImage: "trash")
                }
            }
        }
    }

    private var currentColor: String { (look.color ?? TextLook.colors[0].hex).uppercased() }
    private var currentFill: String { (look.fill ?? "").uppercased() }

    private var sizeBinding: Binding<Double> {
        Binding<Double>(
            get: { TextLook.look(item).size ?? TextLook.defaultSize },
            set: { (px: Double) in item = TextLook.with(item, "size", String(px)) }
        )
    }

    private func swatch(hex: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let fill: Color = hex.isEmpty ? Color.white : Color(uiColor: TextBlockRender.color(hex))
        let traits: AccessibilityTraits = selected ? .isSelected : []
        return Button(action: action) {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                if hex.isEmpty {
                    Rectangle()
                        .fill(Color.red.opacity(0.6))
                        .frame(width: 1.5, height: 22)
                        .rotationEffect(.degrees(45))
                }
            }
            .frame(width: 26, height: 26)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(traits)
    }

    // MARK: how it will look on the board

    private var preview: some View {
        let size: CGSize = TextBlockRender.size(markdown, item: item)
        return ScrollView([.horizontal, .vertical]) {
            TextBlockPreview(markdown: markdown, item: item)
                .frame(width: size.width, height: size.height)
                .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 220)
        .background(Color(white: 0.97))
    }
}

/// A block drawn as the board draws it, for the editor's preview.
private struct TextBlockPreview: UIViewRepresentable {
    var markdown: String
    var item: BoardItem

    func makeUIView(context: Context) -> TextBlockView {
        TextBlockView()
    }

    func updateUIView(_ view: TextBlockView, context: Context) {
        view.update(md: markdown, item: item)
    }
}
