import Foundation
import Darwin

/// Records where the app is stuck when it freezes (Nov 12: opening a PDF froze the whole app on the iPad, and iOS kept no report).
///
/// A background thread asks the main thread to answer every quarter second. When it hasn't answered for 2 seconds, the watcher
/// pauses it for a moment, reads its call stack (the frame-pointer chain), lets it go again, and writes what it saw, with the last
/// few things the app did (`note`), to `diagnostics/ipad-freeze-<time>.txt` in the data folder, which sync brings to the laptop.
/// A stall is sampled again at 5, 10 and 20 seconds, and the file says when it ended (or nothing more, if the app was closed).
final class HangWatch: @unchecked Sendable {
    static let shared = HangWatch()

    private let lock = NSLock()
    private var lastPong = Date()
    private var events: [String] = []
    private var folder: URL?
    private var mainThread: thread_act_t = 0
    private var started = false
    private var build = ""
    /// The stall being recorded: when it began, its file, how many samples it has.
    private var stall: (start: Date, file: URL?, samples: Int)?
    /// Filled while the main thread is paused (nothing may allocate then: the main thread could hold the allocator's lock).
    private let frames = UnsafeMutablePointer<UInt>.allocate(capacity: 160)

    /// Starts watching; call once from the main thread, with the data folder the reports go to.
    func start(folder: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        lock.lock(); self.folder = folder; lock.unlock()
        guard !started else { return }
        started = true
        build = LivePresence.build
        mainThread = mach_thread_self()
        let t = Thread { [unowned self] in self.watch() }
        t.name = "Nexus hang watch"
        t.qualityOfService = .userInitiated
        t.start()
    }

    /// Something the app just did, kept (the last 30) for the next report.
    static func note(_ s: String) { shared.add(s) }

    private func add(_ s: String) {
        let line = Self.clock.string(from: Date()) + "  " + s
        lock.lock()
        events.append(line)
        if events.count > 30 { events.removeFirst(events.count - 30) }
        lock.unlock()
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: watching

    private func watch() {
        let marks: [Double] = [2, 5, 10, 20]
        while true {
            let before = Date()
            Thread.sleep(forTimeInterval: 0.25)
            if Date().timeIntervalSince(before) > 1 {
                // the whole app was paused (in the background): not a freeze
                lock.lock(); lastPong = Date(); lock.unlock()
                stall = nil
                continue
            }
            DispatchQueue.main.async { [self] in lock.lock(); lastPong = Date(); lock.unlock() }
            lock.lock(); let quiet = Date().timeIntervalSince(lastPong); lock.unlock()
            if quiet < 1 {
                if let s = stall { endStall(s, after: Date().timeIntervalSince(s.start)) }
                continue
            }
            if stall == nil { stall = (Date().addingTimeInterval(-quiet), nil, 0) }
            guard var s = stall, s.samples < marks.count, quiet >= marks[s.samples] else { continue }
            let stack = mainStack()
            s.samples += 1
            s.file = write(s, quiet: quiet, stack: stack)
            stall = s
        }
    }

    private func endStall(_ s: (start: Date, file: URL?, samples: Int), after: Double) {
        stall = nil
        guard let file = s.file else { return }
        append(file, String(format: "\nThe main thread answered again after %.1f s.\n", after))
    }

    // MARK: the main thread's stack

    /// The main thread's return addresses, innermost first (pc, lr, then the frame chain).
    private func mainStack() -> [UInt] {
        #if arch(arm64)
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        var n = 0
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &state) { p in
            p.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { thread_get_state(mainThread, thread_state_flavor_t(6), $0, &count) } // ARM_THREAD_STATE64
        }
        if kr == KERN_SUCCESS {
            let strip: UInt = 0x0000_000F_FFFF_FFFF // pointer authentication bits off (system code is arm64e)
            frames[n] = UInt(state.__pc) & strip; n += 1
            frames[n] = UInt(state.__lr) & strip; n += 1
            var fp = UInt(state.__fp)
            var pair: (UInt, UInt) = (0, 0)
            while n < 160, fp != 0, fp % 8 == 0 {
                var got: vm_size_t = 0
                let r = withUnsafeMutablePointer(to: &pair) { p in
                    vm_read_overwrite(mach_task_self_, vm_address_t(fp), 16, vm_address_t(UInt(bitPattern: p)), &got)
                }
                guard r == KERN_SUCCESS, got == 16 else { break }
                let ret = pair.1 & strip
                if ret == 0 { break }
                frames[n] = ret; n += 1
                if pair.0 <= fp { break }
                fp = pair.0
            }
        }
        thread_resume(mainThread)
        return Array(UnsafeBufferPointer(start: frames, count: n))
        #else
        return []
        #endif
    }

    private func describe(_ addrs: [UInt]) -> String {
        var out = ""
        for (i, a) in addrs.enumerated() {
            var info = Dl_info()
            var line = String(format: "%3d  0x%016lx", i, a)
            if dladdr(UnsafeRawPointer(bitPattern: a), &info) != 0 {
                let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
                let base = UInt(bitPattern: info.dli_fbase)
                line += "  " + image + String(format: " +0x%lx", a &- base)
                if let s = info.dli_sname {
                    let name = String(cString: s)
                    line += "  " + Self.demangle(name) + String(format: " +%lu", a &- UInt(bitPattern: info.dli_saddr))
                }
            }
            out += line + "\n"
        }
        return out
    }

    private static func demangle(_ s: String) -> String {
        let raw = s.hasPrefix("_$s") || s.hasPrefix("_T") ? String(s.dropFirst()) : s
        return raw.withCString { p in
            guard let d = swift_demangle(p, UInt(strlen(p)), nil, nil, 0) else { return s }
            defer { free(d) }
            return String(cString: d)
        }
    }

    // MARK: the report

    private func write(_ s: (start: Date, file: URL?, samples: Int), quiet: Double, stack: [UInt]) -> URL? {
        lock.lock(); let recent = events; let root = folder; lock.unlock()
        var text = ""
        if s.file == nil {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
            text += "Nexus on the iPad: the main thread stopped answering at \(f.string(from: s.start)).\n"
            text += "Build \(build), \(ProcessInfo.processInfo.operatingSystemVersionString).\n"
            text += "\nWhat the app did last:\n" + recent.map { "  " + $0 }.joined(separator: "\n") + "\n"
        }
        text += String(format: "\nMain thread after %.1f s:\n", quiet) + describe(stack)
        if let file = s.file { append(file, text); return file }
        guard let root else { return nil }
        let dir = root.appendingPathComponent("diagnostics", isDirectory: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmmss"
        let file = dir.appendingPathComponent("ipad-freeze-\(f.string(from: s.start)).txt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
            prune(dir)
            return file
        } catch { return nil }
    }

    private func append(_ file: URL, _ text: String) {
        guard let h = try? FileHandle(forWritingTo: file) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(text.utf8))
    }

    /// Keeps the newest 20 reports.
    private func prune(_ dir: URL) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("ipad-freeze-") }.sorted()
        for n in names.dropLast(20) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
    }
}

@_silgen_name("swift_demangle")
private func swift_demangle(_ name: UnsafePointer<CChar>?, _ length: UInt, _ out: UnsafeMutablePointer<CChar>?,
                            _ outSize: UnsafeMutablePointer<UInt>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?
