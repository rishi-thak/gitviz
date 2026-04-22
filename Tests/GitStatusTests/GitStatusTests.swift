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

private func sampleStatus(isDirty: Bool, isStaged: Bool) -> GitStatus {
    GitStatus(
        branchName: "main",
        isDirty: isDirty,
        isStaged: isStaged,
        fileCount: 0,
        linesAdded: 0,
        linesRemoved: 0
    )
}
