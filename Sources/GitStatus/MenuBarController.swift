import AppKit

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarController(_ controller: MenuBarController, didSelectRepositoryWithID repositoryID: String)
    func menuBarControllerDidRequestRepositoryRefresh(_ controller: MenuBarController)
    func menuBarControllerDidRequestFullDiff(_ controller: MenuBarController)
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let repositoriesMenu = NSMenu()

    weak var delegate: MenuBarControllerDelegate?

    private lazy var summaryItem: NSMenuItem = {
        let item = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var selectedRepositoryItem: NSMenuItem = {
        let item = NSMenuItem(title: "Repository: none", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var repositoriesItem: NSMenuItem = {
        let item = NSMenuItem(title: "Repositories", action: nil, keyEquivalent: "")
        item.submenu = repositoriesMenu
        return item
    }()

    private lazy var refreshRepositoriesItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Refresh Repositories",
            action: #selector(refreshRepositories),
            keyEquivalent: "r"
        )
        item.target = self
        return item
    }()

    private lazy var discoveryWarningItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.isHidden = true
        return item
    }()

    private lazy var diffItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Show Full Diff",
            action: #selector(showFullDiff),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var quitItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Quit GitStatus",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        item.target = self
        return item
    }()

    private var latestStatus: GitStatus?
    private var selectedRepository: DiscoveredRepository?
    private var repositories: [DiscoveredRepository] = []

    override init() {
        super.init()

        statusItem.button?.title = "..."
        statusItem.button?.toolTip = "GitStatus"
        statusItem.menu = menu

        menu.addItem(summaryItem)
        menu.addItem(selectedRepositoryItem)
        menu.addItem(.separator())
        menu.addItem(repositoriesItem)
        menu.addItem(refreshRepositoriesItem)
        menu.addItem(discoveryWarningItem)
        menu.addItem(.separator())
        menu.addItem(diffItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        rebuildRepositoriesMenu()
    }

    func showLoadingState() {
        summaryItem.title = "Loading repositories..."
        statusItem.button?.title = "..."
        statusItem.button?.toolTip = "Loading repositories"
        selectedRepositoryItem.title = "Repository: none"
    }

    func update(with status: GitStatus) {
        latestStatus = status
        statusItem.button?.title = formattedTitle(for: status)
        statusItem.button?.toolTip = tooltipText(for: status)
        summaryItem.title = statusSummary(for: status)
    }

    func updateSelectedRepository(_ repository: DiscoveredRepository) {
        selectedRepository = repository
        selectedRepositoryItem.title = "Repository: \(repository.name)"

        if latestStatus == nil {
            statusItem.button?.title = "..."
            statusItem.button?.toolTip = repository.path
            summaryItem.title = "Loading git status for \(repository.name)..."
        }

        rebuildRepositoriesMenu()
    }

    func updateRepositories(
        _ repositories: [DiscoveredRepository],
        selectedRepositoryID: String?,
        discoveryWarning: String?
    ) {
        self.repositories = repositories
        if let selectedRepositoryID {
            selectedRepository = repositories.first(where: { $0.id == selectedRepositoryID }) ?? selectedRepository
        }

        discoveryWarningItem.title = discoveryWarning ?? ""
        discoveryWarningItem.isHidden = discoveryWarning == nil

        if let selectedRepository {
            selectedRepositoryItem.title = "Repository: \(selectedRepository.name)"
        } else {
            selectedRepositoryItem.title = "Repository: none"
        }

        rebuildRepositoriesMenu()
    }

    func showNoRepositorySelected(_ message: String) {
        latestStatus = nil
        statusItem.button?.title = "No Repo"
        statusItem.button?.toolTip = message
        summaryItem.title = message
        selectedRepositoryItem.title = "Repository: none"
    }

    func showError(_ message: String) {
        latestStatus = nil
        statusItem.button?.title = "Error"
        statusItem.button?.toolTip = message
        summaryItem.title = message
    }

    func formattedTitle(for status: GitStatus) -> String {
        var suffix = ""

        if status.isDirty {
            suffix += "*"
        }

        if status.isStaged {
            suffix += "+"
        }

        return status.branchName + suffix
    }

    private func tooltipText(for status: GitStatus) -> String {
        let repositoryPath = selectedRepository?.displayPath ?? "No repository selected"
        return "\(repositoryPath) | \(status.branchName) | files: \(status.fileCount) | +\(status.linesAdded) -\(status.linesRemoved)"
    }

    private func statusSummary(for status: GitStatus) -> String {
        let prefix = selectedRepository.map { "\($0.name) | " } ?? ""
        if status.fileCount == 0 {
            return "\(prefix)Branch: \(status.branchName) | Clean"
        }

        return "\(prefix)Branch: \(status.branchName) | files: \(status.fileCount) | +\(status.linesAdded) -\(status.linesRemoved)"
    }

    private func rebuildRepositoriesMenu() {
        repositoriesMenu.removeAllItems()

        if repositories.isEmpty {
            let emptyItem = NSMenuItem(title: "No git repos found in Terminal or iTerm", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            repositoriesMenu.addItem(emptyItem)
            return
        }

        for repository in repositories {
            let item = NSMenuItem(
                title: repository.menuTitle,
                action: #selector(selectRepository(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = repository.id
            item.state = repository.id == selectedRepository?.id ? .on : .off
            repositoriesMenu.addItem(item)
        }
    }

    @objc
    private func showFullDiff() {
        delegate?.menuBarControllerDidRequestFullDiff(self)
    }

    @objc
    private func refreshRepositories() {
        delegate?.menuBarControllerDidRequestRepositoryRefresh(self)
    }

    @objc
    private func selectRepository(_ sender: NSMenuItem) {
        guard let repositoryID = sender.representedObject as? String else { return }
        delegate?.menuBarController(self, didSelectRepositoryWithID: repositoryID)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}
