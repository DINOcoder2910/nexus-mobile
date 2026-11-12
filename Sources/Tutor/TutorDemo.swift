import Foundation
import NexusCore

/// The UI check's tutor (UITests/TutorPanelTests, launched with -NexusTutorDemo): canned replies in place of Claude and a steady pace in
/// place of the voice, so the simulator can photograph the panel going through real turns (the drawing, the chat, your turn). Nothing
/// here runs in a normal launch.
@MainActor
enum TutorDemo {
    static let active = ProcessInfo.processInfo.arguments.contains("-NexusTutorDemo")

    /// Instead of saying a sentence: about as long as saying it would take.
    static func pace(_ sentence: String) async {
        try? await Task.sleep(for: .milliseconds(min(2600, 900 + sentence.count * 24)))
    }

    /// Instead of Claude: the canned reply, streamed in small pieces.
    static func stream(_ words: String, asking: TutorPrompt.Asking, onText: (String) -> Void) async -> ClaudeReply {
        let text = reply(words, asking: asking)
        try? await Task.sleep(for: .milliseconds(1200))
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: 24, limitedBy: text.endIndex) ?? text.endIndex
            onText(String(text[i..<j]))
            i = j
            try? await Task.sleep(for: .milliseconds(20))
        }
        return ClaudeReply(text: text, model: "demo", mode: .api, msToFirstText: 1200)
    }

    static func reply(_ words: String, asking: TutorPrompt.Asking) -> String {
        if asking.practice { return practice }
        if asking.check != nil { return check }
        if asking.hints { return hint }
        return explain
    }

    static let explain = #"""
Let's solve two x plus six equals fourteen.
<step>{"type":"math","id":"eq1","tex":"2x + 6 = 14"}</step>
First we get the x term on its own, so we take six from both sides.
<step>{"type":"math","id":"eq2","tex":"2x = 8"}</step>
<step>{"type":"text","text":"− 6 both sides","color":"grey","size":"small","at":{"right":"eq2"}}</step>
That leaves two x equals eight.
<step>{"type":"point","target":{"in":"eq2","part":"8"}}</step>
Then we divide both sides by two, which undoes the times two.
<step>{"type":"math","id":"eq3","tex":"x = 4","color":"green"}</step>
<step>{"type":"text","text":"÷ 2 both sides","color":"grey","size":"small","at":{"right":"eq3"}}</step>
So x is four.
<step>{"type":"box","target":"eq3","color":"green"}</step>
You can check it: two times four plus six is fourteen.
"""#

    static let practice = #"""
Here is one like it for you to try.
<step>{"type":"text","id":"t1","text":"Try one","size":"large"}</step>
<step>{"type":"math","id":"p1","tex":"3x - 5 = 16"}</step>
<step>{"type":"box","target":"p1","color":"blue"}</step>
It is the same idea: get the x term on its own first, then divide.
<step>{"type":"yourturn","ask":"Solve 3x − 5 = 16 on the board, then press Check my work."}</step>
"""#

    static let hint = #"""
Look at the minus five first.
<step>{"type":"underline","target":{"in":"p1","part":"- 5"},"brief":true,"color":"orange"}</step>
What would undo taking away five?
<step>{"type":"yourturn","ask":"Write the line you get after undoing the minus five."}</step>
"""#

    static let check = #"""
That's right, x is seven.
<step>{"type":"text","text":"x = 7 ✓","color":"green","size":"large"}</step>
Adding five gives three x equals twenty-one, and dividing by three gives seven.
"""#
}
