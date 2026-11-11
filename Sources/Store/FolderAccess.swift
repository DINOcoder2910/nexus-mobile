import Foundation

/// Where the data folder is on the iPad, and reading and writing its files.
///
/// By default it is `On My iPad › Nexus › nexus-data` (the app's own Documents), which sync with the laptop and the G14 will fill.
/// A folder picked from Files (another app's storage) is kept as a bookmark and read and written with file coordination, so the app
/// that owns it sees each change.
enum FolderAccess {
    static let bookmarkKey = "dataFolderBookmark"

    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var defaultFolder: URL { documents.appendingPathComponent("nexus-data", isDirectory: true) }

    /// The picked folder, or the default one.
    static func current() -> (url: URL, picked: Bool) {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                }
                return (url, true)
            }
        }
        try? FileManager.default.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        return (defaultFolder, false)
    }

    /// Remembers a folder picked in Files.
    static func pick(_ url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func useDefault() { UserDefaults.standard.removeObject(forKey: bookmarkKey) }

    /// Coordinated read: waits for another writer (a file provider, sync) to finish.
    static func read(_ url: URL) throws -> String {
        var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = Result { String(decoding: try Data(contentsOf: u), as: UTF8.self) }
        }
        if let coordError { throw coordError }
        return try result.get()
    }

    /// Coordinated, atomic write.
    static func write(_ url: URL, _ text: String) throws {
        var result: Result<Void, Error> = .success(())
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordError) { u in
            result = Result {
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: u, options: .atomic)
            }
        }
        if let coordError { throw coordError }
        try result.get()
    }

    /// Coordinated, atomic write of bytes (an image or a PDF put on a board).
    static func writeData(_ url: URL, _ data: Data) throws {
        var result: Result<Void, Error> = .success(())
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordError) { u in
            result = Result {
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: u, options: .atomic)
            }
        }
        if let coordError { throw coordError }
        try result.get()
    }
}
