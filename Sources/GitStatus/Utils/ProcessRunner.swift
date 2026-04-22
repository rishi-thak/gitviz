import Foundation

enum ProcessRunner {
    struct Result: Sendable {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32
    }

    enum Error: LocalizedError {
        case launchFailed(executable: String, underlying: Swift.Error)
        case executionFailed(executable: String, status: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case let .launchFailed(executable, underlying):
                return "Failed to launch \(executable): \(underlying.localizedDescription)"
            case let .executionFailed(executable, status, stderr):
                let reason = stderr.isEmpty ? "Unknown error" : stderr
                return "\(executable) failed with exit code \(status): \(reason)"
            }
        }
    }

    static func run(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws -> Result {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw Error.launchFailed(executable: executablePath, underlying: error)
        }

        process.waitUntilExit()

        let stdout = String(
            decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .newlines)
        let stderr = String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            stdout: stdout,
            stderr: stderr,
            terminationStatus: process.terminationStatus
        )
    }
}
