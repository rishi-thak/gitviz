import Darwin
import Foundation

enum BackgroundLauncher {
    private static let backgroundFlag = "--background-launch"
    private static let foregroundFlag = "--foreground-launch"

    static func bootstrapIfNeeded() {
        let arguments = CommandLine.arguments

        guard !arguments.contains(backgroundFlag) else { return }
        guard !arguments.contains(foregroundFlag) else { return }
        guard launchedFromInteractiveShell else { return }

        do {
            try relaunchDetached()
            exit(EXIT_SUCCESS)
        } catch {
            let message = "GitStatus warning: failed to detach background process (\(error.localizedDescription)). Continuing in the current process.\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }

    private static var launchedFromInteractiveShell: Bool {
        isatty(STDIN_FILENO) == 1 || isatty(STDOUT_FILENO) == 1 || isatty(STDERR_FILENO) == 1
    }

    private static func relaunchDetached() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [backgroundFlag]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        try process.run()
    }
}
