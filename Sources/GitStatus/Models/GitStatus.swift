import Foundation

struct GitStatus: Codable, Equatable, Sendable {
    let branchName: String
    let isDirty: Bool
    let isStaged: Bool
    let fileCount: Int
    let linesAdded: Int
    let linesRemoved: Int
    let commitsAheadOfMain: Int?
    let commitsBehindMain: Int?

    var mainComparisonSummary: String {
        guard let commitsAheadOfMain, let commitsBehindMain else {
            return "vs main: unavailable"
        }

        return "vs main: ahead \(commitsAheadOfMain), behind \(commitsBehindMain)"
    }

    enum CodingKeys: String, CodingKey {
        case branchName = "branch_name"
        case isDirty = "is_dirty"
        case isStaged = "is_staged"
        case fileCount = "file_count"
        case linesAdded = "lines_added"
        case linesRemoved = "lines_removed"
        case commitsAheadOfMain = "commits_ahead_of_main"
        case commitsBehindMain = "commits_behind_main"
    }
}
