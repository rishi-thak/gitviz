import Foundation

struct GitChangeCounts: Equatable, Sendable {
    let stagedFiles: Int
    let unstagedFiles: Int
    let untrackedFiles: Int

    var totalTrackedChanges: Int {
        stagedFiles + unstagedFiles
    }
}

struct GitDiffSnapshot: Equatable, Sendable {
    let repositoryName: String
    let repositoryPath: String
    let branchName: String
    let generatedAt: Date
    let changeCounts: GitChangeCounts
    let porcelainStatus: String
    let stagedShortStat: String
    let unstagedShortStat: String
    let stagedStat: String
    let unstagedStat: String
    let stagedPatch: String
    let unstagedPatch: String
}
