import Foundation
import NexusCore

/// The screenshots' Claude (UITests/ClaudeChatUITests and ClaudeChatPhoneTests, launched with -NexusClaudeDemo): canned replies in place
/// of Claude, made from what the app sends, so the simulator photographs real turns on the sample data: a look-up, a proposed change,
/// Plan with Claude placing a slipped task, the day brief. Nothing here runs in a normal launch.
enum ClaudeDemo {
    static let active = ProcessInfo.processInfo.arguments.contains("-NexusClaudeDemo")

    static func stream(_ req: ClaudeRequest, onText: @escaping (String) -> Void) async -> ClaudeReply {
        let text = reply(req)
        try? await Task.sleep(for: .milliseconds(700))
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: 24, limitedBy: text.endIndex) ?? text.endIndex
            onText(String(text[i..<j]))
            i = j
            try? await Task.sleep(for: .milliseconds(15))
        }
        return ClaudeReply(text: text, model: "demo", mode: .api, msToFirstText: 700, stopReason: "end_turn")
    }

    static func reply(_ req: ClaudeRequest) -> String {
        if req.system == DayBrief.system { return brief }
        let last = req.messages.last?.text ?? ""
        if last.contains(ClaudeChat.planHead) { return plan(last) }
        if let inbox = result("read inbox.yaml", in: last) { return fileInbox(inbox) }
        return "I'll look at your Inbox first.\n<read path=\"inbox.yaml\"/>"
    }

    static let brief = "Redox worksheet and the physics questions make up your day, with the Physics HW sheet due in two days. Reading 4.2 on waves slipped from two days ago; I can place it this afternoon with you. Ms Settle has had the lab report for three days."

    /// The text of a `<result of="…">` block in a message.
    static func result(_ of: String, in text: String) -> String? {
        guard let a = text.range(of: "<result of=\"\(of)\">\n"), let b = text.range(of: "\n</result>", range: a.upperBound..<text.endIndex) else { return nil }
        return String(text[a.upperBound..<b.lowerBound])
    }

    static func fileInbox(_ inbox: String) -> String {
        let lines = inbox.components(separatedBy: "\n")
        guard let k = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- id:") }), k + 1 < lines.count else {
            return "Your Inbox is empty, so there is nothing to file."
        }
        let title = lines[k + 1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "title: ", with: "")
        let indent = String(lines[k + 1].prefix { $0 == " " })
        let tomorrow = Days.add(Days.today(), 1)
        return """
        One thing is waiting to be filed: **\(title)**. It doesn't belong to a class yet, so I'd keep it in the Inbox and give it a deadline of tomorrow, so it shows on Today:
        <edit path="inbox.yaml">
        <old>
        \(lines[k])
        \(lines[k + 1])
        </old>
        <new>
        \(lines[k])
        \(lines[k + 1])
        \(indent)due: \(tomorrow)
        </new>
        </edit>
        *Learn to juggle* stays in Someday.
        """
    }

    /// Plan with Claude: each slipped task gets the next free half hour (or its length) today.
    static func plan(_ prompt: String) -> String {
        let today = prompt.components(separatedBy: "Today is ").dropFirst().first.map { String($0.prefix(10)) } ?? Days.today()
        var start = 16 * 60 + 30
        if let free = prompt.components(separatedBy: "Free today: ").dropFirst().first, let first = free.split(separator: ",").first,
           let dash = first.firstIndex(of: "-"), let m = DayLayout.minutes(String(first[..<dash])) { start = max(m, 9 * 60) }
        var out: [String] = []
        var placed: [String] = []
        for line in prompt.components(separatedBy: "\n") where line.hasPrefix("- ") {
            // - <id> "<title>" in <path>, about <n>m
            let parts = line.dropFirst(2).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let inAt = line.range(of: "\" in "), let about = line.range(of: ", about ") else { continue }
            let id = String(parts[0])
            let path = String(line[inAt.upperBound..<about.lowerBound])
            let mins = Int(line[about.upperBound...].dropLast()) ?? 30
            guard let file = result("read \(path)", in: prompt), let edit = placeEdit(id: id, file: file, at: "\(today) \(DayLayout.hhmm(start))") else { continue }
            out.append("<edit path=\"\(path)\">\n<old>\n\(edit.old)\n</old>\n<new>\n\(edit.new)\n</new>\n</edit>")
            placed.append(String(line[line.index(after: line.firstIndex(of: "\"")!)..<inAt.lowerBound]) + " at " + DayLayout.hhmm(start))
            start += max(30, (mins + 4) / 5 * 5)
        }
        if out.isEmpty { return "Nothing slipped that I could place today." }
        return "I put \(placed.joined(separator: " and ")) into today's free time.\n" + out.joined(separator: "\n") + "\nEverything fitted."
    }

    /// The lines of task `id` up to its plan (or its title), and the same with `entry` added to its plan.
    static func placeEdit(id: String, file: String, at entry: String) -> (old: String, new: String)? {
        let lines = file.components(separatedBy: "\n")
        guard let k = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "- id: \(id)" }) else { return nil }
        let field = String(repeating: " ", count: lines[k].prefix { $0 == " " }.count + 2)
        var end = k
        var j = k + 1
        while j < lines.count, lines[j].hasPrefix(field), !lines[j].hasPrefix(field + " ") || lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
            if lines[j].hasPrefix(field + "plan: [") {
                let old = lines[k...j].joined(separator: "\n")
                var newPlan = lines[j]
                if let close = newPlan.lastIndex(of: "]") { newPlan.insert(contentsOf: ", " + entry, at: close) }
                return (old, (Array(lines[k..<j]) + [newPlan]).joined(separator: "\n"))
            }
            if lines[j].hasPrefix(field + "title:") { end = j }
            if lines[j].hasPrefix(field + "subtasks:") { break }
            j += 1
        }
        let old = lines[k...end].joined(separator: "\n")
        return (old, old + "\n" + field + "plan: [\(entry)]")
    }
}
