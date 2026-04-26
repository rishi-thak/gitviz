import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarControllerDelegate {
    private let menuBarController = MenuBarController()
    private var gitStatusMonitor: GitStatusMonitor?
    private var repositoryDiscoveryService: RepositoryDiscoveryService?
    private var gitDiffWindowController: GitDiffWindowController?
    private var selectedRepository: DiscoveredRepository?
    private var discoveredRepositories: [DiscoveredRepository] = []
    private let launchDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstanceLock.acquire() else {
            NSApp.terminate(nil)
            return
        }

        menuBarController.delegate = self
        menuBarController.showLoadingState()

        gitStatusMonitor = GitStatusMonitor(
            onStatusUpdate: { [weak self] status in
                self?.menuBarController.update(with: status)
            },
            onError: { [weak self] message in
                self?.menuBarController.showError(message)
            }
        )
        gitStatusMonitor?.start()

        repositoryDiscoveryService = RepositoryDiscoveryService(
            launchDirectoryURL: launchDirectoryURL,
            onRepositoriesUpdated: { [weak self] repositories, warning in
                self?.handleRepositoryUpdate(repositories, warning: warning)
            }
        )
        repositoryDiscoveryService?.start()

        if let launchRepository = try? GitCommand.repositoryRoot(for: launchDirectoryURL) {
            let fallbackRepository = DiscoveredRepository(
                path: launchRepository.path,
                name: launchRepository.lastPathComponent,
                sourceLabels: ["Launch Directory"],
                sessionCount: 1
            )
            selectRepository(fallbackRepository)
            menuBarController.updateRepositories(
                [fallbackRepository],
                selectedRepositoryID: fallbackRepository.id,
                discoveryWarning: nil
            )
        } else {
            menuBarController.showNoRepositorySelected("No git repository selected")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        repositoryDiscoveryService?.stop()
        gitStatusMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuBarController(_ controller: MenuBarController, didSelectRepositoryWithID repositoryID: String) {
        guard let repository = discoveredRepositories.first(where: { $0.id == repositoryID }) else { return }
        selectRepository(repository)
    }

    func menuBarControllerDidRequestRepositoryRefresh(_ controller: MenuBarController) {
        repositoryDiscoveryService?.refreshNow()
    }

    func menuBarControllerDidRequestFullDiff(_ controller: MenuBarController) {
        guard let repository = selectedRepository else {
            menuBarController.showNoRepositorySelected("No repository selected for diff")
            return
        }

        showFullDiff(for: repository)
    }

    private func handleRepositoryUpdate(_ repositories: [DiscoveredRepository], warning: String?) {
        discoveredRepositories = repositories

        if let selectedRepository, repositories.contains(where: { $0.id == selectedRepository.id }) {
            if let refreshedSelection = repositories.first(where: { $0.id == selectedRepository.id }) {
                self.selectedRepository = refreshedSelection
            }
        } else if let firstRepository = repositories.first {
            selectRepository(firstRepository)
        } else {
            selectedRepository = nil
            menuBarController.showNoRepositorySelected("No git repositories found in Terminal or iTerm")
            gitStatusMonitor?.setRepository(nil)
        }

        menuBarController.updateRepositories(
            repositories,
            selectedRepositoryID: selectedRepository?.id,
            discoveryWarning: warning
        )
    }

    private func selectRepository(_ repository: DiscoveredRepository) {
        selectedRepository = repository
        gitStatusMonitor?.setRepository(repository.url)
        menuBarController.updateSelectedRepository(repository)
    }

    private func showFullDiff(for repository: DiscoveredRepository) {
        let windowController = gitDiffWindowController ?? GitDiffWindowController()
        gitDiffWindowController = windowController
        windowController.onRefresh = { [weak self] in
            guard let self, let repository = self.selectedRepository else { return }
            self.showFullDiff(for: repository)
        }
        windowController.showLoading(for: repository)

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let snapshot = try GitCommand.diffSnapshot(for: repository.url)
                await MainActor.run {
                    guard
                        let self,
                        self.gitDiffWindowController?.displayingRepositoryID == repository.id
                    else { return }

                    self.gitDiffWindowController?.show(snapshot: snapshot, repositoryID: repository.id)
                }
            } catch {
                await MainActor.run {
                    guard
                        let self,
                        self.gitDiffWindowController?.displayingRepositoryID == repository.id
                    else { return }

                    self.gitDiffWindowController?.showError(error.localizedDescription, repository: repository)
                }
            }
        }
    }
}
