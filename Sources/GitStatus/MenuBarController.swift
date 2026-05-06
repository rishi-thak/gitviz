import AppKit

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarController(_ controller: MenuBarController, didSelectRepositoryWithID repositoryID: String)
    func menuBarControllerDidRequestRefresh(_ controller: MenuBarController)
    func menuBarControllerDidRequestFullDiff(_ controller: MenuBarController)
    func menuBarControllerDidRequestOpenInFinder(_ controller: MenuBarController)
    func menuBarController(_ controller: MenuBarController, didRequestAddCommitPushWithMessage message: String)
    func menuBarControllerDidRequestPullUpstream(_ controller: MenuBarController)
    func menuBarControllerDidRequestPullCurrentBranch(_ controller: MenuBarController)
}

@MainActor
final class MenuBarController: NSObject, NSTextFieldDelegate {
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
            title: "Refresh Now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        item.target = self
        return item
    }()

    private lazy var lastUpdatedItem: NSMenuItem = {
        let item = NSMenuItem(title: "Last updated: never", action: nil, keyEquivalent: "")
        item.isEnabled = false
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

    private lazy var openInFinderItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Open in Finder",
            action: #selector(openInFinder),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var commitPromptItem: NSMenuItem = {
        let item = NSMenuItem(title: "Commit message", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var commitMessageField: NSTextField = {
        let field = NSTextField(string: "")
        field.placeholderString = "what should this commit be called?"
        field.delegate = self
        field.lineBreakMode = .byTruncatingTail
        field.target = self
        field.action = #selector(runAddCommitPush)
        return field
    }()

    private lazy var commitMessageItem: NSMenuItem = {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        commitMessageField.frame = NSRect(x: 10, y: 2, width: 260, height: 24)
        container.addSubview(commitMessageField)
        item.view = container
        return item
    }()

    private lazy var addCommitPushItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "ACP",
            action: #selector(runAddCommitPush),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var pullUpstreamItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Pull Upstream",
            action: #selector(pullUpstream),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var pullCurrentBranchItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Pull Current Branch",
            action: #selector(pullCurrentBranch),
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
    private var lastUpdatedAt: Date?
    private var isRefreshing = false
    private var isGitActionRunning = false
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    override init() {
        super.init()

        statusItem.button?.title = "..."
        statusItem.button?.toolTip = "GitStatus"
        statusItem.menu = menu

        menu.addItem(summaryItem)
        menu.addItem(selectedRepositoryItem)
        menu.addItem(lastUpdatedItem)
        menu.addItem(.separator())
        menu.addItem(diffItem)
        menu.addItem(openInFinderItem)
        menu.addItem(.separator())
        menu.addItem(commitPromptItem)
        menu.addItem(commitMessageItem)
        menu.addItem(addCommitPushItem)
        menu.addItem(pullUpstreamItem)
        menu.addItem(pullCurrentBranchItem)
        menu.addItem(.separator())
        menu.addItem(repositoriesItem)
        menu.addItem(refreshRepositoriesItem)
        menu.addItem(discoveryWarningItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        rebuildRepositoriesMenu()
    }

    func showLoadingState() {
        isRefreshing = true
        summaryItem.title = "Loading repositories..."
        statusItem.button?.title = "..."
        statusItem.button?.toolTip = "Loading repositories"
        selectedRepositoryItem.title = "Repository: none"
        lastUpdatedAt = nil
        updateRefreshUI()
    }

    func update(with status: GitStatus) {
        latestStatus = status
        isRefreshing = false
        lastUpdatedAt = Date()
        statusItem.button?.title = formattedTitle(for: status)
        statusItem.button?.toolTip = tooltipText(for: status)
        summaryItem.title = statusSummary(for: status)
        updateRefreshUI()
    }

    func updateSelectedRepository(_ repository: DiscoveredRepository) {
        selectedRepository = repository
        latestStatus = nil
        isRefreshing = true
        selectedRepositoryItem.title = "Repository: \(repository.name)"

        statusItem.button?.title = "..."
        statusItem.button?.toolTip = repository.path
        summaryItem.title = "Loading git status for \(repository.name)..."
        updateRefreshUI()

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
        } else {
            selectedRepository = nil
        }

        discoveryWarningItem.title = discoveryWarning ?? ""
        discoveryWarningItem.isHidden = discoveryWarning == nil

        if let selectedRepository {
            selectedRepositoryItem.title = "Repository: \(selectedRepository.name)"
        } else {
            selectedRepositoryItem.title = "Repository: none"
        }

        updateRefreshUI()

        rebuildRepositoriesMenu()
    }

    func showNoRepositorySelected(_ message: String) {
        latestStatus = nil
        isRefreshing = false
        statusItem.button?.title = "No Repo"
        statusItem.button?.toolTip = message
        summaryItem.title = message
        selectedRepositoryItem.title = "Repository: none"
        updateRefreshUI()
    }

    func showError(_ message: String) {
        latestStatus = nil
        isRefreshing = false
        statusItem.button?.title = "Error"
        statusItem.button?.toolTip = message
        summaryItem.title = message
        updateRefreshUI()
    }

    func showRefreshingStatus() {
        isRefreshing = true
        summaryItem.title = selectedRepository.map { "Refreshing \($0.name)..." } ?? "Refreshing..."
        updateRefreshUI()
    }

    func finishRefreshing() {
        isRefreshing = false
        lastUpdatedAt = Date()
        if let latestStatus {
            summaryItem.title = statusSummary(for: latestStatus)
        }
        updateRefreshUI()
    }

    func showGitActionInProgress(_ message: String) {
        isGitActionRunning = true
        summaryItem.title = message
        updateRefreshUI()
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
        return "\(repositoryPath) | \(status.branchName) | \(status.upstreamComparisonSummary) | files: \(status.fileCount) | +\(status.linesAdded) -\(status.linesRemoved)"
    }

    private func statusSummary(for status: GitStatus) -> String {
        let prefix = selectedRepository.map { "\($0.name) | " } ?? ""
        if status.fileCount == 0 {
            return "\(prefix)Branch: \(status.branchName) | \(status.upstreamComparisonSummary) | Clean"
        }

        return "\(prefix)Branch: \(status.branchName) | \(status.upstreamComparisonSummary) | files: \(status.fileCount) | +\(status.linesAdded) -\(status.linesRemoved)"
    }

    private func updateRefreshUI() {
        if isRefreshing {
            refreshRepositoriesItem.title = "Refreshing..."
            refreshRepositoriesItem.isEnabled = false
        } else {
            refreshRepositoriesItem.title = "Refresh Now"
            refreshRepositoriesItem.isEnabled = selectedRepository != nil
        }

        if let lastUpdatedAt {
            lastUpdatedItem.title = "Last updated: \(timestampFormatter.string(from: lastUpdatedAt))"
        } else {
            lastUpdatedItem.title = isRefreshing ? "Last updated: refreshing..." : "Last updated: never"
        }

        let hasSelection = selectedRepository != nil
        let isActionable = hasSelection && !isGitActionRunning

        diffItem.isEnabled = hasSelection
        openInFinderItem.isEnabled = hasSelection
        commitMessageField.isEnabled = isActionable
        addCommitPushItem.isEnabled = isActionable && !commitMessageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        pullUpstreamItem.isEnabled = isActionable
        pullCurrentBranchItem.isEnabled = isActionable
        updatePullMenuTitles()
    }

    private func updatePullMenuTitles() {
        guard let latestStatus else {
            pullUpstreamItem.title = "Pull Upstream"
            pullCurrentBranchItem.title = "Pull Current Branch"
            return
        }

        if let upstreamBranchName = latestStatus.upstreamBranchName {
            pullUpstreamItem.title = "Pull \(upstreamBranchName)"
        } else {
            pullUpstreamItem.title = "Pull Upstream"
        }

        pullCurrentBranchItem.title = "Pull \(latestStatus.branchName)"
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
    private func refreshNow() {
        showRefreshingStatus()
        delegate?.menuBarControllerDidRequestRefresh(self)
    }

    @objc
    private func selectRepository(_ sender: NSMenuItem) {
        guard let repositoryID = sender.representedObject as? String else { return }
        delegate?.menuBarController(self, didSelectRepositoryWithID: repositoryID)
    }

    @objc
    private func openInFinder() {
        delegate?.menuBarControllerDidRequestOpenInFinder(self)
    }

    func controlTextDidChange(_ obj: Notification) {
        updateRefreshUI()
    }

    @objc
    private func runAddCommitPush() {
        let message = commitMessageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        delegate?.menuBarController(self, didRequestAddCommitPushWithMessage: message)
    }

    @objc
    private func pullUpstream() {
        delegate?.menuBarControllerDidRequestPullUpstream(self)
    }

    @objc
    private func pullCurrentBranch() {
        delegate?.menuBarControllerDidRequestPullCurrentBranch(self)
    }

    func clearCommitMessageInput() {
        commitMessageField.stringValue = ""
        updateRefreshUI()
    }

    func finishGitAction() {
        isGitActionRunning = false
        updateRefreshUI()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

#if DEBUG
extension MenuBarController {
    var selectedRepositoryIDForTesting: String? {
        selectedRepository?.id
    }

    var statusItemTitleForTesting: String? {
        statusItem.button?.title
    }

    var summaryTitleForTesting: String {
        summaryItem.title
    }

    var lastUpdatedTitleForTesting: String {
        lastUpdatedItem.title
    }

    var refreshTitleForTesting: String {
        refreshRepositoriesItem.title
    }

    var pullUpstreamTitleForTesting: String {
        pullUpstreamItem.title
    }

    var pullCurrentBranchTitleForTesting: String {
        pullCurrentBranchItem.title
    }
}
#endif
