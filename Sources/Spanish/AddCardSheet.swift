import SwiftUI
import NexusCore

/// Add a card (or Add to vocab from a checked word, or Add to deck from the tutor's offer): the two sides, the deck (the vocab deck of the
/// unit being taught now unless you pick another), tags and an example; the card rules are shown as warnings, never enforced; the card
/// is written at the end of the deck's cards (SpanishCards.addCardText keeps the rest of the file as it was).
struct SpanishAddCardSheet: View {
    let workstreamId: String
    var draft = SpanishCards.Draft()
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var front = ""
    @State private var back = ""
    @State private var deck = ""
    @State private var tags = ""
    @State private var example = ""
    @State private var ready = false
    @FocusState private var field: String?

    var lib: SpanishLibrary { .shared }

    var body: some View {
        let decks = lib.decks(workstreamId)
        NavigationStack {
            Form {
                if decks.isEmpty {
                    Text("There is no Spanish deck in study/decks/ yet. Set up Spanish study writes them.").foregroundStyle(.secondary)
                } else {
                    Section {
                        TextField("Spanish", text: $front).focused($field, equals: "front").autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("spanish-card-front")
                        TextField("English", text: $back).focused($field, equals: "back").textInputAutocapitalization(.never)
                            .accessibilityIdentifier("spanish-card-back")
                    }
                    Section {
                        Picker("Deck", selection: $deck) {
                            ForEach(decks, id: \.deck.id) { d in Text(d.deck.title).tag(d.deck.id) }
                        }
                        TextField("Tags: pos::sustantivo, tema::experiencias, irr::o-ue, frase", text: $tags).autocorrectionDisabled().textInputAutocapitalization(.never)
                        TextField("Example: a short sentence that uses it (optional)", text: $example, axis: .vertical).autocorrectionDisabled()
                    }
                    let warn = SpanishCards.warnings(front: front, back: back, tags: tagList, existing: existing(decks))
                    if !warn.isEmpty {
                        Section {
                            ForEach(warn, id: \.self) { w in Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.soon).font(.callout) }
                        }
                    }
                    Section {
                        Text("Nouns with their article; phrases are fine; skip cognates; for verbs, only the irregular forms. One card per word: the deck can be shown either way round.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(draft.front.isEmpty ? "Add a card" : "Add to vocab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add the card") { add(decks) }
                        .disabled(decks.isEmpty || front.trimmingCharacters(in: .whitespaces).isEmpty || back.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("spanish-card-add")
                }
            }
            .onAppear {
                guard !ready else { return }
                ready = true
                front = draft.front; back = draft.back; tags = draft.tags.joined(separator: ", "); example = draft.example
                let ids = decks.map(\.deck.id)
                deck = ids.contains(draft.deck) ? draft.deck : ids.contains(lib.defaultDeck(workstreamId)) ? lib.defaultDeck(workstreamId) : (ids.first ?? "")
                field = front.isEmpty ? "front" : "back"
            }
        }
    }

    private var tagList: [String] { tags.split(separator: ",").map { Spanish.cleanTag(String($0)) }.filter { !$0.isEmpty } }

    private func existing(_ decks: [(path: String, deck: StudyDeck)]) -> [SpanishCards.Existing] {
        decks.flatMap { d in d.deck.cards.map { SpanishCards.Existing(front: $0.front, back: $0.back, deck: d.deck.title) } }
    }

    private func add(_ decks: [(path: String, deck: StudyDeck)]) {
        guard let d = decks.first(where: { $0.deck.id == deck }) else { return }
        let card = SpanishCards.Draft(front: front.trimmingCharacters(in: .whitespaces), back: back.trimmingCharacters(in: .whitespaces), deck: deck, tags: tagList, example: example.trimmingCharacters(in: .whitespacesAndNewlines))
        if lib.addCard(store, workstreamId, deckPath: d.path, card) != nil {
            store.toast = .init(message: "Added to \(d.deck.title): \(card.front)")
            dismiss()
        }
    }
}
