import AppKit

final class GitDiffWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class GitDiffWindowController: NSWindowController {
    private enum Style {
        @MainActor static var bodyFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }
        @MainActor static var highlightedFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold) }
        @MainActor static var sectionFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .medium) }
        @MainActor static var bodyColor: NSColor { .textColor }
        @MainActor static var highlightedColor: NSColor { .systemCyan }
        @MainActor static var sectionColor: NSColor { .systemOrange }
    }

    var onRefresh: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Git Diff")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let textView = NSTextView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    private(set) var displayingRepositoryID: String?

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 920, height: 680)
        let window = GitDiffWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Git Diff"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showLoading(for repository: DiscoveredRepository) {
        displayingRepositoryID = repository.id
        titleLabel.stringValue = "Git Diff - \(repository.name)"
        subtitleLabel.stringValue = repository.displayPath
        updateText("Loading diff for \(repository.name)...")
        presentWindow()
    }

    func show(snapshot: GitDiffSnapshot, repositoryID: String) {
        displayingRepositoryID = repositoryID
        titleLabel.stringValue = "Git Diff - \(snapshot.repositoryName)"
        subtitleLabel.stringValue = snapshot.repositoryPath
        updateText(GitDiffReportRenderer.render(snapshot))
        presentWindow()
    }

    func showError(_ message: String, repository: DiscoveredRepository) {
        displayingRepositoryID = repository.id
        titleLabel.stringValue = "Git Diff - \(repository.name)"
        subtitleLabel.stringValue = repository.displayPath
        updateText("Unable to load diff.\n\n\(message)")
        presentWindow()
    }

    private func configureWindow() {
        guard let window else { return }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = container

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        refreshButton.bezelStyle = .rounded

        textView.frame = NSRect(x: 0, y: 0, width: 880, height: 640)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = Style.bodyFont
        textView.textColor = Style.bodyColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        let headerStack = NSStackView(views: [titleLabel, NSView(), refreshButton])
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(headerStack)
        container.addSubview(subtitleLabel)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
    }

    private func updateText(_ text: String) {
        textView.textStorage?.setAttributedString(makeAttributedText(from: text))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }

    private func makeAttributedText(from text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Style.bodyFont,
                .foregroundColor: Style.bodyColor,
            ]
        )

        let lines = text.components(separatedBy: .newlines)
        let highlightedLineCount = min(4, lines.count)
        var currentLocation = 0

        for (index, line) in lines.enumerated() {
            let lineLength = (line as NSString).length
            let newlineLength = index < lines.count - 1 ? 1 : 0

            if index < highlightedLineCount {
                attributed.addAttributes(
                    [
                        .font: Style.highlightedFont,
                        .foregroundColor: Style.highlightedColor,
                    ],
                    range: NSRange(location: currentLocation, length: lineLength)
                )
            } else if shouldHighlightSectionLine(line) {
                attributed.addAttributes(
                    [
                        .font: Style.sectionFont,
                        .foregroundColor: Style.sectionColor,
                    ],
                    range: NSRange(location: currentLocation, length: lineLength)
                )
            }

            currentLocation += lineLength + newlineLength
        }

        return attributed
    }

    private func shouldHighlightSectionLine(_ line: String) -> Bool {
        if line.isEmpty {
            return false
        }

        if line == "Change Counts" {
            return true
        }

        if line.hasPrefix("Status (--porcelain)") ||
            line.hasPrefix("Staged Summary (--shortstat)") ||
            line.hasPrefix("Unstaged Summary (--shortstat)") ||
            line.hasPrefix("Staged File Stats (--stat)") ||
            line.hasPrefix("Unstaged File Stats (--stat)") ||
            line.hasPrefix("Staged Patch") ||
            line.hasPrefix("Unstaged Patch") {
            return true
        }

        if line.hasPrefix("- ") {
            return true
        }

        return false
    }

    private func presentWindow() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc
    private func refreshClicked() {
        onRefresh?()
    }
}
