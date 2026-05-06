import Foundation

struct GitStatus: Codable, Equatable, Sendable {
    let branchName: String
    let isDirty: Bool
    let isStaged: Bool
    let fileCount: Int
    let linesAdded: Int
    let linesRemoved: Int
    let upstreamBranchName: String?
    let upstreamRemoteName: String?
    let commitsAheadOfUpstream: Int?
    let commitsBehindUpstream: Int?

    var upstreamComparisonSummary: String {
        guard
            let upstreamBranchName,
            let commitsAheadOfUpstream,
            let commitsBehindUpstream
        else {
            return "vs upstream: unavailable"
        }

        return "vs \(upstreamBranchName): ahead \(commitsAheadOfUpstream), behind \(commitsBehindUpstream)"
    }

    enum CodingKeys: String, CodingKey {
        case branchName = "branch_name"
        case isDirty = "is_dirty"
        case isStaged = "is_staged"
        case fileCount = "file_count"
        case linesAdded = "lines_added"
        case linesRemoved = "lines_removed"
        case upstreamBranchName = "upstream_branch_name"
        case upstreamRemoteName = "upstream_remote_name"
        case commitsAheadOfUpstream = "commits_ahead_of_upstream"
        case commitsBehindUpstream = "commits_behind_upstream"
    }
}
