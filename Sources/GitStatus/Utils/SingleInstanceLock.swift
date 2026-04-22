import Darwin
import Foundation

@MainActor
enum SingleInstanceLock {
    private static var lockFileDescriptor: Int32 = -1

    static func acquire() -> Bool {
        guard lockFileDescriptor == -1 else { return true }

        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GitStatus", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        } catch {
            return true
        }

        let lockFilePath = supportDirectory.appendingPathComponent("GitStatus.lock").path
        let descriptor = open(lockFilePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return true }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        lockFileDescriptor = descriptor
        return true
    }
}
