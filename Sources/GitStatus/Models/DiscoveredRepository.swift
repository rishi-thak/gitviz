import Foundation

struct DiscoveredRepository: Hashable, Identifiable, Sendable {
    let path: String
    let name: String
    let sourceLabels: [String]
    let sessionCount: Int

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    var displayPath: String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(homeDirectory) else { return path }

        let suffix = path.dropFirst(homeDirectory.count)
        return suffix.isEmpty ? "~" : "~\(suffix)"
    }

    var menuTitle: String {
        let sessionLabel = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        return "\(name) - \(displayPath) [\(sourceLabels.joined(separator: ", ")); \(sessionLabel)]"
    }
}
