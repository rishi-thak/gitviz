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
}
