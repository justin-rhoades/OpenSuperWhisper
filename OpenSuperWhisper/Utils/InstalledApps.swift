import AppKit
import Foundation

/// A user-facing application discovered on disk, used by the app-aware formatting picker so the
/// user chooses an app from a list instead of typing its bundle identifier.
struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let url: URL
}

enum InstalledApps {
    /// Standard locations where `.app` bundles live. Covers the vast majority of apps; anything
    /// outside these can still be added via the picker's "Browse…" (NSOpenPanel) escape hatch.
    private static let searchRoots: [URL] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ].map { URL(fileURLWithPath: $0) }

    /// All installed apps, de-duplicated by bundle id and sorted by display name.
    static func all() -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for root in searchRoots {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])) ?? []
            for url in items where url.pathExtension == "app" {
                guard let app = app(at: url), !seen.contains(app.bundleIdentifier) else { continue }
                seen.insert(app.bundleIdentifier)
                result.append(app)
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads an `.app` bundle into an `InstalledApp` (nil if it has no bundle identifier).
    static func app(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return InstalledApp(bundleIdentifier: bid, name: name, url: url)
    }

    /// Icon for a discovered app.
    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Best-effort icon for an already-stored bundle id (so existing profiles show the app icon
    /// even though they only persist the identifier). Falls back to a generic app icon.
    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
