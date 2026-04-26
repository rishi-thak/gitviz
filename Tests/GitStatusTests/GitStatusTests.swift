import Foundation
import Testing
@testable import GitStatus

@Test
@MainActor
func menuBarFormattingReflectsGitState() {
    let controller = MenuBarController()

    #expect(controller.formattedTitle(for: sampleStatus(isDirty: true, isStaged: false)) == "main*")
    #expect(controller.formattedTitle(for: sampleStatus(isDirty: false, isStaged: true)) == "main+")
    #expect(controller.formattedTitle(for: sampleStatus(isDirty: false, isStaged: false)) == "main")
    #expect(controller.formattedTitle(for: sampleStatus(isDirty: true, isStaged: true)) == "main*+")
}

@Test
@MainActor
func menuBarClearsSelectionWhenNoRepositoriesRemain() {
    let controller = MenuBarController()
    let repository = DiscoveredRepository(
        path: "/tmp/gitviz",
        name: "gitviz",
        sourceLabels: ["Terminal"],
        sessionCount: 1
    )

    controller.updateRepositories([repository], selectedRepositoryID: repository.id, discoveryWarning: nil)
    #expect(controller.selectedRepositoryIDForTesting == repository.id)

    controller.updateRepositories([], selectedRepositoryID: nil, discoveryWarning: nil)
    #expect(controller.selectedRepositoryIDForTesting == nil)
}

@Test
func gitStatusFormatsMainComparisonSummary() {
    let comparedStatus = sampleStatus(isDirty: false, isStaged: false, commitsAheadOfMain: 3, commitsBehindMain: 1)
    let unavailableStatus = sampleStatus(isDirty: false, isStaged: false)

    #expect(comparedStatus.mainComparisonSummary == "vs main: ahead 3, behind 1")
    #expect(unavailableStatus.mainComparisonSummary == "vs main: unavailable")
}

@Test
func discoveredRepositoryUsesReadableMenuTitle() {
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    let repository = DiscoveredRepository(
        path: "\(homeDirectory)/Code/gitviz",
        name: "gitviz",
        sourceLabels: ["Terminal", "iTerm"],
        sessionCount: 3
    )

    #expect(repository.menuTitle.contains("gitviz"))
    #expect(repository.menuTitle.contains("~/Code/gitviz"))
    #expect(repository.displayPath == "~/Code/gitviz")
}

@Test
func gitDiffReportIncludesStatSections() {
    let snapshot = GitDiffSnapshot(
        repositoryName: "gitviz",
        repositoryPath: "/tmp/gitviz",
        branchName: "main",
        generatedAt: Date(timeIntervalSince1970: 0),
        changeCounts: GitChangeCounts(stagedFiles: 2, unstagedFiles: 1, untrackedFiles: 3),
        porcelainStatus: "M  README.md",
        stagedShortStat: "1 file changed, 4 insertions(+)",
        unstagedShortStat: "1 file changed, 2 deletions(-)",
        stagedStat: "README.md | 4 ++++",
        unstagedStat: "AppDelegate.swift | 2 --",
        stagedPatch: "diff --git a/README.md b/README.md",
        unstagedPatch: "diff --git a/AppDelegate.swift b/AppDelegate.swift"
    )

    let report = GitDiffReportRenderer.render(snapshot)

    #expect(report.contains("Staged Summary (--shortstat)"))
    #expect(report.contains("Unstaged Summary (--shortstat)"))
    #expect(report.contains("Staged File Stats (--stat)"))
    #expect(report.contains("Unstaged File Stats (--stat)"))
    #expect(report.contains("Staged Patch"))
    #expect(report.contains("Unstaged Patch"))
    #expect(report.contains("Untracked files: 3"))
}

private func sampleStatus(
    isDirty: Bool,
    isStaged: Bool,
    commitsAheadOfMain: Int? = nil,
    commitsBehindMain: Int? = nil
) -> GitStatus {
    GitStatus(
        branchName: "main",
        isDirty: isDirty,
        isStaged: isStaged,
        fileCount: 0,
        linesAdded: 0,
        linesRemoved: 0,
        commitsAheadOfMain: commitsAheadOfMain,
        commitsBehindMain: commitsBehindMain
    )
}
