import Foundation

enum GitCommand {
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
        let branchName = try run(
            arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)

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
