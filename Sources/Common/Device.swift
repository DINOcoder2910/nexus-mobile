import UIKit

/// Which device the app runs on: the same app runs on the iPad and the iPhone, and the words it shows name the right one.
enum Device {
    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    /// "iPhone" or "iPad", as the Files app says it ("On My iPhone").
    static var name: String { isPhone ? "iPhone" : "iPad" }
    /// Where the data folder is by default, as the Files app shows it.
    static var defaultFolder: String { "On My \(name) › Nexus › nexus-data" }
}
