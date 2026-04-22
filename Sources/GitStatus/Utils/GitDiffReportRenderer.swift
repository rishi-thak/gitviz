import Foundation

enum GitDiffReportRenderer {
    static func render(_ snapshot: GitDiffSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let statusSection = snapshot.porcelainStatus.isEmpty ? "Working tree clean." : snapshot.porcelainStatus
        let stagedShortStat = snapshot.stagedShortStat.isEmpty ? "No staged changes." : snapshot.stagedShortStat
        let unstagedShortStat = snapshot.unstagedShortStat.isEmpty ? "No unstaged changes." : snapshot.unstagedShortStat
        let stagedStat = snapshot.stagedStat.isEmpty ? "No staged file diff stats." : snapshot.stagedStat
        let unstagedStat = snapshot.unstagedStat.isEmpty ? "No unstaged file diff stats." : snapshot.unstagedStat
        let stagedPatch = snapshot.stagedPatch.isEmpty ? "No staged patch output." : snapshot.stagedPatch
        let unstagedPatch = snapshot.unstagedPatch.isEmpty ? "No unstaged patch output." : snapshot.unstagedPatch

        return """
        Repository: \(snapshot.repositoryName)
        Path: \(snapshot.repositoryPath)
        Branch: \(snapshot.branchName)
        Generated: \(formatter.string(from: snapshot.generatedAt))

        Change Counts
        - Staged files: \(snapshot.changeCounts.stagedFiles)
        - Unstaged files: \(snapshot.changeCounts.unstagedFiles)
        - Untracked files: \(snapshot.changeCounts.untrackedFiles)
        - Total tracked changes: \(snapshot.changeCounts.totalTrackedChanges)

        Status (--porcelain)
        \(statusSection)

        Staged Summary (--shortstat)
        \(stagedShortStat)

        Unstaged Summary (--shortstat)
        \(unstagedShortStat)

        Staged File Stats (--stat)
        \(stagedStat)

        Unstaged File Stats (--stat)
        \(unstagedStat)

        Staged Patch
        \(stagedPatch)

        Unstaged Patch
        \(unstagedPatch)
        """
    }
}
