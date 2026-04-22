import Foundation

struct GitStatus: Codable, Equatable, Sendable {
    let branchName: String
    let isDirty: Bool
    let isStaged: Bool
    let fileCount: Int
    let linesAdded: Int
    let linesRemoved: Int

    enum CodingKeys: String, CodingKey {
        case branchName = "branch_name"
        case isDirty = "is_dirty"
        case isStaged = "is_staged"
        case fileCount = "file_count"
        case linesAdded = "lines_added"
        case linesRemoved = "lines_removed"
    }
}
