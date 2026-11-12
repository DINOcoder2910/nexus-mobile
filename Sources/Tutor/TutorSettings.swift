import SwiftUI
import Speech
import AVFoundation

/// Settings › Tutor: the voice for English and for Spanish (by accent, with each voice's quality and a button to hear it), how fast it
/// talks, and the language the tutor listens in. The same voices read aloud on boards.
struct TutorSettings: View {
    @AppStorage(Voices.englishKey) private var english = ""
    @AppStorage(Voices.spanishKey) private var spanish = ""
    @AppStorage(Voices.rateKey) private var rate: Double = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage(Voices.listenKey) private var listen = ""

    var body: some View {
        Section {
            VoicePicker(title: "English voice", lang: "en", sample: "Oxidation is loss of electrons, and reduction is gain.", choice: $english)
            VoicePicker(title: "Spanish voice", lang: "es", sample: "Ayer fui al mercado con mi hermana y compramos fruta.", choice: $spanish)
            VStack(alignment: .leading) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(rate < 0.45 ? "Slow" : rate > 0.55 ? "Fast" : "Normal").foregroundStyle(.secondary)
                }
                Slider(value: $rate, in: 0.35...0.65) { Text("Speed") }
            }
            Picker("Listens in", selection: $listen) {
                Text("The iPad's language").tag("")
                ForEach(listenLocales, id: \.self) { id in Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id) }
            }
        } header: { Text("Tutor and Read aloud") } footer: {
            Text("Apple's voices, free and offline. Each sentence is read in its language, so Spanish is said in the Spanish voice. Better voices (Enhanced and Premium) download once in iPad Settings › Accessibility › Read & Speak › Voices; they show up here after that.")
        }
        Section {
            Button("Open iPad Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
        }
    }

    var listenLocales: [String] {
        SFSpeechRecognizer.supportedLocales().map(\.identifier).filter { $0.hasPrefix("en") || $0.hasPrefix("es") }.sorted()
    }
}

/// One language's voices, by accent, best first.
struct VoicePicker: View {
    let title: String
    let lang: String
    let sample: String
    @Binding var choice: String

    var body: some View {
        let all = Voices.options(lang)
        let accents = Array(Set(all.map(\.accent))).sorted()
        NavigationLink {
            List {
                ForEach(accents, id: \.self) { accent in
                    Section(accent) {
                        ForEach(all.filter { $0.accent == accent }) { v in
                            HStack {
                                Button {
                                    choice = v.id
                                    hear(v.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(v.name)
                                            Text(v.quality).font(.caption).foregroundStyle(v.rank > 1 ? Color.accentColor : .secondary)
                                        }
                                        Spacer()
                                        if v.id == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button { hear(v.id) } label: { Image(systemName: "play.circle") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Hear \(v.name)")
                            }
                        }
                    }
                }
                if all.isEmpty { Text("This iPad has no \(lang == "es" ? "Spanish" : "English") voices yet. Add one in iPad Settings › Accessibility › Read & Speak › Voices.") }
            }
            .navigationTitle(title)
        } label: {
            LabeledContent(title, value: label(all))
        }
    }

    var current: String { choice.isEmpty ? (Voices.voice(lang)?.identifier ?? "") : choice }

    func label(_ all: [Voices.Option]) -> String {
        guard let v = all.first(where: { $0.id == current }) else { return "Automatic" }
        return "\(v.name) · \(v.accent)"
    }

    func hear(_ id: String) {
        let u = AVSpeechUtterance(string: sample)
        u.voice = AVSpeechSynthesisVoice(identifier: id)
        u.rate = Voices.rate
        Speaker.shared.stop()
        Audio.prepareForSpeaking()
        Speaker.shared.synth.speak(u)
    }
}
