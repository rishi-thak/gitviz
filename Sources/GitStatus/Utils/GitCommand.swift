import Foundation

enum GitCommand {
    struct UpstreamReference: Equatable, Sendable {
        let remoteName: String
        let branchName: String

        var displayName: String {
            "\(remoteName)/\(branchName)"
        }
    }

    enum Error: LocalizedError {
        case executionFailed(command: String, status: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case let .executionFailed(command, status, stderr):
                let reason = stderr.isEmpty ? "Unknown git error" : stderr
                return "\(command) failed with exit code \(status): \(reason)"
            }
        }
    }

    @discardableResult
    static func run(arguments: [String], in directoryURL: URL) throws -> String {
        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/env",
            arguments: ["git"] + arguments,
            currentDirectoryURL: directoryURL
        )

        guard result.terminationStatus == 0 else {
            throw Error.executionFailed(
                command: "git " + arguments.joined(separator: " "),
                status: result.terminationStatus,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    static func repositoryRoot(for directoryURL: URL) throws -> URL {
        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/env",
            arguments: ["git", "-C", directoryURL.path, "rev-parse", "--show-toplevel"]
        )

        guard result.terminationStatus == 0 else {
            throw Error.executionFailed(
                command: "git -C \(directoryURL.path) rev-parse --show-toplevel",
                status: result.terminationStatus,
                stderr: result.stderr
            )
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: output).standardizedFileURL
    }

    static func diffSnapshot(for repositoryURL: URL) throws -> GitDiffSnapshot {
        let branchName = try currentBranchName(in: repositoryURL)

        let porcelainStatus = try run(
            arguments: ["status", "--porcelain"],
            in: repositoryURL
        )

        let changeCounts = parseChangeCounts(from: porcelainStatus)

        let stagedShortStat = try run(
            arguments: ["diff", "--cached", "--shortstat"],
            in: repositoryURL
        )
        let unstagedShortStat = try run(
            arguments: ["diff", "--shortstat"],
            in: repositoryURL
        )
        let stagedStat = try run(
            arguments: ["diff", "--cached", "--stat"],
            in: repositoryURL
        )
        let unstagedStat = try run(
            arguments: ["diff", "--stat"],
            in: repositoryURL
        )
        let stagedPatch = try run(
            arguments: ["diff", "--cached"],
            in: repositoryURL
        )
        let unstagedPatch = try run(
            arguments: ["diff"],
            in: repositoryURL
        )

        return GitDiffSnapshot(
            repositoryName: repositoryURL.lastPathComponent,
            repositoryPath: repositoryURL.path,
            branchName: branchName,
            generatedAt: Date(),
            changeCounts: changeCounts,
            porcelainStatus: porcelainStatus,
            stagedShortStat: stagedShortStat,
            unstagedShortStat: unstagedShortStat,
            stagedStat: stagedStat,
            unstagedStat: unstagedStat,
            stagedPatch: stagedPatch,
            unstagedPatch: unstagedPatch
        )
    }

    static func currentBranchName(in repositoryURL: URL) throws -> String {
        try run(
            arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func upstreamReference(for repositoryURL: URL) throws -> UpstreamReference? {
        let upstreamName = try run(
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !upstreamName.isEmpty else { return nil }

        let parts = upstreamName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw Error.executionFailed(
                command: "git rev-parse --abbrev-ref --symbolic-full-name @{upstream}",
                status: 1,
                stderr: "Unexpected upstream format: \(upstreamName)"
            )
        }

        return UpstreamReference(remoteName: parts[0], branchName: parts[1])
    }

    static func addCommitPush(message: String, in repositoryURL: URL) throws {
        try run(arguments: ["add", "."], in: repositoryURL)
        try run(arguments: ["commit", "-m", message], in: repositoryURL)
        let currentBranch = try currentBranchName(in: repositoryURL)
        try run(arguments: ["push", "origin", currentBranch], in: repositoryURL)
    }

    static func pullUpstream(in repositoryURL: URL) throws {
        guard let upstream = try upstreamReference(for: repositoryURL) else {
            throw Error.executionFailed(
                command: "git pull @{upstream}",
                status: 1,
                stderr: "No upstream branch configured"
            )
        }

        try run(arguments: ["pull", upstream.remoteName, upstream.branchName], in: repositoryURL)
    }

    static func pullCurrentBranch(in repositoryURL: URL) throws {
        let currentBranch = try currentBranchName(in: repositoryURL)
        let remoteName = (try? upstreamReference(for: repositoryURL)?.remoteName) ?? "origin"
        try run(arguments: ["pull", remoteName, currentBranch], in: repositoryURL)
    }

    private static func parseChangeCounts(from porcelainStatus: String) -> GitChangeCounts {
        var stagedFiles = 0
        var unstagedFiles = 0
        var untrackedFiles = 0

        for rawLine in porcelainStatus.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.count >= 2 else { continue }

            let indexStatus = line[line.startIndex]
            let workingStatus = line[line.index(after: line.startIndex)]

            if indexStatus == "?" && workingStatus == "?" {
                untrackedFiles += 1
                continue
            }

            if indexStatus != " " {
                stagedFiles += 1
            }

            if workingStatus != " " {
                unstagedFiles += 1
            }
        }

        return GitChangeCounts(
            stagedFiles: stagedFiles,
            unstagedFiles: unstagedFiles,
            untrackedFiles: untrackedFiles
        )
    }
}
