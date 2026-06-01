import AppKit
import Darwin
import Dispatch
import Foundation

final class RepositoryDiscoveryService: @unchecked Sendable {
    private enum TerminalProvider {
        case terminal
        case iTerm

        var label: String {
            switch self {
            case .terminal:
                return "Terminal"
            case .iTerm:
                return "iTerm"
            }
        }

        var bundleIdentifier: String {
            switch self {
            case .terminal:
                return "com.apple.Terminal"
            case .iTerm:
                return "com.googlecode.iterm2"
            }
        }

        var ttyScriptLines: [String] {
            switch self {
            case .terminal:
                return [
                    "tell application \"Terminal\"",
                    "set outputText to \"\"",
                    "repeat with aWindow in windows",
                    "repeat with aTab in tabs of aWindow",
                    "try",
                    "set outputText to outputText & (tty of aTab) & linefeed",
                    "end try",
                    "end repeat",
                    "end repeat",
                    "return outputText",
                    "end tell",
                ]
            case .iTerm:
                return [
                    "tell application \"iTerm2\"",
                    "set outputText to \"\"",
                    "repeat with aWindow in windows",
                    "repeat with aTab in tabs of aWindow",
                    "repeat with aSession in sessions of aTab",
                    "try",
                    "set outputText to outputText & (tty of aSession) & linefeed",
                    "end try",
                    "end repeat",
                    "end repeat",
                    "end repeat",
                    "return outputText",
                    "end tell",
                ]
            }
        }
    }

    private struct RepositoryAccumulator {
        let path: String
        let name: String
        var sourceLabels: Set<String>
        var sessionCount: Int
    }

    private let launchDirectoryURL: URL
    private let onRepositoriesUpdated: @MainActor @Sendable ([DiscoveredRepository], String?) -> Void
    private let queue = DispatchQueue(label: "RepositoryDiscoveryService.queue", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastRepositories: [DiscoveredRepository] = []
    private var lastWarning: String?
    private var isRunning = false

    init(
        launchDirectoryURL: URL,
        onRepositoriesUpdated: @escaping @MainActor @Sendable ([DiscoveredRepository], String?) -> Void
    ) {
        self.launchDirectoryURL = launchDirectoryURL
        self.onRepositoriesUpdated = onRepositoriesUpdated
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = true
            self.refresh()
            self.startTimerIfNeeded()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            timer?.cancel()
            timer = nil
        }
    }

    func refreshNow() {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.refresh()
        }
    }

    private func startTimerIfNeeded() {
        guard isRunning else { return }
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        self.timer = timer
        timer.resume()
    }

    private func refresh() {
        guard isRunning else { return }
        var repositoriesByPath: [String: RepositoryAccumulator] = [:]
        var warnings: [String] = []

        for provider in [TerminalProvider.terminal, .iTerm] {
            guard providerIsRunning(provider) else { continue }

            do {
                let ttys = try fetchTTYs(for: provider)
                for tty in ttys {
                    let repositories = repositoriesForTTY(tty)
                    for repositoryURL in repositories {
                        mergeRepository(
                            repositoryURL,
                            sourceLabel: provider.label,
                            into: &repositoriesByPath
                        )
                    }
                }
            } catch {
                if let warning = warningMessage(for: provider, error: error) {
                    warnings.append(warning)
                }
            }
        }

        if let fallbackRepository = try? GitCommand.repositoryRoot(for: launchDirectoryURL) {
            mergeRepository(
                fallbackRepository,
                sourceLabel: "Launch Directory",
                into: &repositoriesByPath
            )
        }

        let repositories = repositoriesByPath.values
            .map {
                DiscoveredRepository(
                    path: $0.path,
                    name: $0.name,
                    sourceLabels: $0.sourceLabels.sorted(),
                    sessionCount: $0.sessionCount
                )
            }
            .sorted {
                if $0.sessionCount == $1.sessionCount {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                return $0.sessionCount > $1.sessionCount
            }

        let warning = warnings.isEmpty ? nil : warnings.joined(separator: " | ")
        guard repositories != lastRepositories || warning != lastWarning else { return }

        lastRepositories = repositories
        lastWarning = warning

        Task { @MainActor [onRepositoriesUpdated] in
            onRepositoriesUpdated(repositories, warning)
        }
    }

    private func providerIsRunning(_ provider: TerminalProvider) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: provider.bundleIdentifier).isEmpty
    }

    private func fetchTTYs(for provider: TerminalProvider) throws -> [String] {
        let output = try runAppleScript(lines: provider.ttyScriptLines)
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func repositoriesForTTY(_ ttyPath: String) -> Set<URL> {
        guard let ttyName = ttyPath.split(separator: "/").last.map(String.init) else { return [] }

        let pidOutput = (try? ProcessRunner.run(
            executablePath: "/bin/ps",
            arguments: ["-t", ttyName, "-o", "pid="]
        ).stdout) ?? ""

        let processIDs = pidOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 != getpid() }

        var repositories: Set<URL> = []

        for processID in processIDs {
            guard let cwd = currentWorkingDirectory(forProcessID: processID) else { continue }
            guard let repositoryURL = try? GitCommand.repositoryRoot(for: cwd) else { continue }
            repositories.insert(repositoryURL)
        }

        return repositories
    }

    private func currentWorkingDirectory(forProcessID processID: Int32) -> URL? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let ret = proc_pidinfo(processID, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard ret == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { buf -> String? in
            guard let base = buf.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func mergeRepository(
        _ repositoryURL: URL,
        sourceLabel: String,
        into repositoriesByPath: inout [String: RepositoryAccumulator]
    ) {
        let path = repositoryURL.standardizedFileURL.path

        if var existing = repositoriesByPath[path] {
            existing.sourceLabels.insert(sourceLabel)
            existing.sessionCount += 1
            repositoriesByPath[path] = existing
        } else {
            repositoriesByPath[path] = RepositoryAccumulator(
                path: path,
                name: repositoryURL.lastPathComponent,
                sourceLabels: [sourceLabel],
                sessionCount: 1
            )
        }
    }

    private func runAppleScript(lines: [String]) throws -> String {
        var arguments: [String] = ["-l", "AppleScript"]
        for line in lines {
            arguments.append("-e")
            arguments.append(line)
        }

        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/osascript",
            arguments: arguments
        )

        guard result.terminationStatus == 0 else {
            throw ProcessRunner.Error.executionFailed(
                executable: "/usr/bin/osascript",
                status: result.terminationStatus,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    private func warningMessage(for provider: TerminalProvider, error: Swift.Error) -> String? {
        let description = error.localizedDescription

        if description.contains("-1743") || description.localizedCaseInsensitiveContains("not authorized") {
            return "Allow GitStatus to control \(provider.label) in System Settings > Privacy & Security > Automation."
        }

        return "Unable to inspect \(provider.label): \(description)"
    }
}
