import Darwin
import Dispatch
import Foundation

final class GitStatusMonitor: @unchecked Sendable {
    private let onStatusUpdate: @MainActor @Sendable (GitStatus) -> Void
    private let onError: @MainActor @Sendable (String) -> Void
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "GitStatusMonitor.queue", qos: .utility)

    private var repositoryURL: URL?
    private var gitDirectoryURL: URL?
    private var watcherSources: [DispatchSourceFileSystemObject] = []
    private var fallbackTimer: DispatchSourceTimer?
    private var refreshWorkItem: DispatchWorkItem?
    private var lastPublishedStatus: GitStatus?
    private var lastErrorMessage: String?

    init(
        onStatusUpdate: @escaping @MainActor @Sendable (GitStatus) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.onStatusUpdate = onStatusUpdate
        self.onError = onError
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.startFallbackTimerIfNeeded()
            self.rebindRepository()
        }
    }

    func stop() {
        queue.sync {
            refreshWorkItem?.cancel()
            refreshWorkItem = nil

            fallbackTimer?.cancel()
            fallbackTimer = nil

            watcherSources.forEach { $0.cancel() }
            watcherSources.removeAll()
        }
    }

    func setRepository(_ repositoryURL: URL?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.repositoryURL = repositoryURL?.standardizedFileURL
            self.lastPublishedStatus = nil
            self.lastErrorMessage = nil
            self.rebindRepository()
        }
    }

    private func rebindRepository() {
        guard let repositoryURL else {
            gitDirectoryURL = nil
            clearWatchers()
            return
        }

        do {
            let resolvedGitDirectoryURL = try resolveGitDirectory(for: repositoryURL)

            if gitDirectoryURL?.path != resolvedGitDirectoryURL.path || watcherSources.isEmpty {
                gitDirectoryURL = resolvedGitDirectoryURL
                installWatchers(for: resolvedGitDirectoryURL)
            }

            scheduleRefresh()
        } catch {
            gitDirectoryURL = nil
            clearWatchers()
            publish(error: error.localizedDescription)
        }
    }

    private func resolveGitDirectory(for repositoryURL: URL) throws -> URL {
        let gitDirOutput = try GitCommand.run(
            arguments: ["rev-parse", "--git-dir"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let rawURL = URL(fileURLWithPath: gitDirOutput, relativeTo: repositoryURL)
        let resolvedURL = rawURL.standardizedFileURL

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GitCommand.Error.executionFailed(
                command: "git rev-parse --git-dir",
                status: 1,
                stderr: "Resolved .git path does not exist: \(resolvedURL.path)"
            )
        }

        return resolvedURL
    }

    private func installWatchers(for gitDirectoryURL: URL) {
        clearWatchers()

        let watchURLs = [
            gitDirectoryURL,
            gitDirectoryURL.appendingPathComponent("HEAD"),
            gitDirectoryURL.appendingPathComponent("index"),
        ]

        for watchURL in watchURLs where fileManager.fileExists(atPath: watchURL.path) {
            let descriptor = open(watchURL.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
                queue: queue
            )

            source.setEventHandler { [weak self, weak source] in
                guard let self else { return }

                let flags = source?.data ?? []
                if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                    self.rebindRepository()
                    return
                }

                self.scheduleRefresh()
            }

            source.setCancelHandler {
                close(descriptor)
            }

            watcherSources.append(source)
            source.resume()
        }
    }

    private func clearWatchers() {
        watcherSources.forEach { $0.cancel() }
        watcherSources.removeAll()
    }

    private func startFallbackTimerIfNeeded() {
        guard fallbackTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.repositoryURL != nil else { return }
            self.scheduleRefresh()
        }

        fallbackTimer = timer
        timer.resume()
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshStatus()
        }

        refreshWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func refreshStatus() {
        guard let repositoryURL else { return }

        do {
            let status = try fetchStatus(in: repositoryURL)
            publish(status: status)
        } catch {
            publish(error: error.localizedDescription)
        }
    }

    private func fetchStatus(in repositoryURL: URL) throws -> GitStatus {
        let branchOutput = try GitCommand.run(
            arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let branchName: String
        if branchOutput == "HEAD" {
            branchName = try GitCommand.run(
                arguments: ["rev-parse", "--short", "HEAD"],
                in: repositoryURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            branchName = branchOutput
        }

        let porcelain = try GitCommand.run(
            arguments: ["status", "--porcelain"],
            in: repositoryURL
        )

        let stagedDiffStat = try GitCommand.run(
            arguments: ["diff", "--stat", "--cached"],
            in: repositoryURL
        )

        let unstagedDiffStat = try GitCommand.run(
            arguments: ["diff", "--stat"],
            in: repositoryURL
        )

        let parsedStatus = parsePorcelainStatus(porcelain)
        let stagedTotals = parseDiffStat(stagedDiffStat)
        let unstagedTotals = parseDiffStat(unstagedDiffStat)

        return GitStatus(
            branchName: branchName,
            isDirty: parsedStatus.isDirty,
            isStaged: parsedStatus.isStaged,
            fileCount: parsedStatus.fileCount,
            linesAdded: stagedTotals.added + unstagedTotals.added,
            linesRemoved: stagedTotals.removed + unstagedTotals.removed
        )
    }

    private func parsePorcelainStatus(_ output: String) -> (isDirty: Bool, isStaged: Bool, fileCount: Int) {
        var isDirty = false
        var isStaged = false
        var fileCount = 0

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.count >= 2 else { continue }

            fileCount += 1

            let indexStatus = line[line.startIndex]
            let workingStatus = line[line.index(after: line.startIndex)]

            if indexStatus != " " && indexStatus != "?" {
                isStaged = true
            }

            if workingStatus != " " || indexStatus == "?" || workingStatus == "?" {
                isDirty = true
            }
        }

        return (isDirty, isStaged, fileCount)
    }

    private func parseDiffStat(_ output: String) -> (added: Int, removed: Int) {
        guard let summaryLine = output
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init)
        else {
            return (0, 0)
        }

        return (
            added: extractCount(matching: #"(\d+)\sinsertions?\(\+\)"#, in: summaryLine),
            removed: extractCount(matching: #"(\d+)\sdeletions?\(-\)"#, in: summaryLine)
        )
    }

    private func extractCount(matching pattern: String, in summaryLine: String) -> Int {
        guard
            let regularExpression = try? NSRegularExpression(pattern: pattern),
            let match = regularExpression.firstMatch(
                in: summaryLine,
                range: NSRange(summaryLine.startIndex..., in: summaryLine)
            ),
            let range = Range(match.range(at: 1), in: summaryLine)
        else {
            return 0
        }

        return Int(summaryLine[range]) ?? 0
    }

    private func publish(status: GitStatus) {
        guard lastPublishedStatus != status || lastErrorMessage != nil else { return }

        lastPublishedStatus = status
        lastErrorMessage = nil

        Task { @MainActor [onStatusUpdate] in
            onStatusUpdate(status)
        }
    }

    private func publish(error message: String) {
        guard lastErrorMessage != message else { return }

        lastPublishedStatus = nil
        lastErrorMessage = message

        Task { @MainActor [onError] in
            onError(message)
        }
    }
}
