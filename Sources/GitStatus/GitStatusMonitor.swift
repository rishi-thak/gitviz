import Darwin
import Dispatch
import Foundation

final class GitStatusMonitor: @unchecked Sendable {
    private let onStatusUpdate: @MainActor @Sendable (GitStatus) -> Void
    private let onError: @MainActor @Sendable (String) -> Void
    private let onRefreshFinished: @MainActor @Sendable () -> Void
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "GitStatusMonitor.queue", qos: .utility)

    private var repositoryURL: URL?
    private var gitDirectoryURL: URL?
    private var watcherSources: [DispatchSourceFileSystemObject] = []
    private var fallbackTimer: DispatchSourceTimer?
    private var refreshWorkItem: DispatchWorkItem?
    private var lastPublishedStatus: GitStatus?
    private var lastErrorMessage: String?
    private var isRunning = false

    init(
        onStatusUpdate: @escaping @MainActor @Sendable (GitStatus) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void,
        onRefreshFinished: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onStatusUpdate = onStatusUpdate
        self.onError = onError
        self.onRefreshFinished = onRefreshFinished
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = true
            self.startFallbackTimerIfNeeded()
            self.rebindRepository()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            refreshWorkItem?.cancel()
            refreshWorkItem = nil

            fallbackTimer?.cancel()
            fallbackTimer = nil

            clearWatchers()
        }
    }

    func setRepository(_ repositoryURL: URL?) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else { return }
            self.repositoryURL = repositoryURL?.standardizedFileURL
            self.lastPublishedStatus = nil
            self.lastErrorMessage = nil
            self.rebindRepository()
        }
    }

    func refreshNow() {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.scheduleRefresh()
        }
    }

    private func rebindRepository() {
        guard isRunning else { return }

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
        guard isRunning else { return }
        guard fallbackTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self, self.repositoryURL != nil else { return }
            self.scheduleRefresh()
        }

        fallbackTimer = timer
        timer.resume()
    }

    private func scheduleRefresh() {
        guard isRunning else { return }
        refreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshStatus()
        }

        refreshWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func refreshStatus() {
        guard isRunning else { return }
        guard let repositoryURL else { return }

        defer {
            if isRunning {
                Task { @MainActor [onRefreshFinished] in
                    onRefreshFinished()
                }
            }
        }

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

        let stagedNumstat = try GitCommand.run(
            arguments: ["diff", "--numstat", "--cached"],
            in: repositoryURL
        )

        let unstagedNumstat = try GitCommand.run(
            arguments: ["diff", "--numstat"],
            in: repositoryURL
        )

        let parsedStatus = parsePorcelainStatus(porcelain)
        let stagedTotals = parseNumstat(stagedNumstat)
        let unstagedTotals = parseNumstat(unstagedNumstat)
        let upstreamComparison = fetchUpstreamComparison(in: repositoryURL)

        return GitStatus(
            branchName: branchName,
            isDirty: parsedStatus.isDirty,
            isStaged: parsedStatus.isStaged,
            fileCount: parsedStatus.fileCount,
            linesAdded: stagedTotals.added + unstagedTotals.added,
            linesRemoved: stagedTotals.removed + unstagedTotals.removed,
            upstreamBranchName: upstreamComparison?.branchName,
            upstreamRemoteName: upstreamComparison?.remoteName,
            commitsAheadOfUpstream: upstreamComparison?.ahead,
            commitsBehindUpstream: upstreamComparison?.behind
        )
    }

    private func fetchUpstreamComparison(in repositoryURL: URL) -> (remoteName: String, branchName: String, ahead: Int, behind: Int)? {
        guard let upstreamReference = try? GitCommand.upstreamReference(for: repositoryURL)
        else {
            return nil
        }

        guard let output = try? GitCommand.run(
            arguments: ["rev-list", "--left-right", "--count", "\(upstreamReference.displayName)...HEAD"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let parts = output.split(whereSeparator: \.isWhitespace)
        guard
            parts.count == 2,
            let behind = Int(parts[0]),
            let ahead = Int(parts[1])
        else {
            return nil
        }

        return (
            remoteName: upstreamReference.remoteName,
            branchName: upstreamReference.displayName,
            ahead: ahead,
            behind: behind
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

    private func parseNumstat(_ output: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count >= 2 else { continue }
            added += Int(parts[0]) ?? 0
            removed += Int(parts[1]) ?? 0
        }
        return (added, removed)
    }

    private func publish(status: GitStatus) {
        guard isRunning else { return }
        guard lastPublishedStatus != status || lastErrorMessage != nil else { return }

        lastPublishedStatus = status
        lastErrorMessage = nil

        Task { @MainActor [onStatusUpdate] in
            onStatusUpdate(status)
        }
    }

    private func publish(error message: String) {
        guard isRunning else { return }
        guard lastErrorMessage != message else { return }

        lastPublishedStatus = nil
        lastErrorMessage = message

        Task { @MainActor [onError] in
            onError(message)
        }
    }
}
