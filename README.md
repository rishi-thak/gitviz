# gitviz

A macOS menu bar app that shows live git status for the repository you're currently working in. It auto-discovers git repos from open Terminal and iTerm2 sessions, polls for changes by watching the `.git` directory with `DispatchSource`, and surfaces branch name, dirty/staged state, line counts, and upstream comparison — all from the menu bar.

---

## Features

- **Live status in the menu bar** — branch name with `*` (dirty) and `+` (staged) indicators update in real time
- **Auto-discovery** — finds git repositories from every open tab/session in Terminal and iTerm2 via AppleScript; no manual configuration
- **Repository switcher** — if multiple repos are open, pick one from the Repositories submenu
- **Upstream tracking** — shows commits ahead/behind the upstream branch
- **Full diff viewer** — opens a window with staged and unstaged diffs (`git diff --stat` + full patch)
- **ACP (Add, Commit, Push)** — type a commit message in the menu and hit Enter to `git add . && git commit -m "..." && git push origin <branch>` in one action
- **Pull** — pull from the upstream branch or the current branch's remote with a single click
- **Open in Finder** — reveals the repository root in Finder
- **Single-instance lock** — a second launch of the same binary exits immediately
- **Background detach** — when launched from a terminal, the process re-launches itself detached so it doesn't block the shell

---

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`)
- Git available at `/usr/bin/git`
- **Automation** permission for Terminal and/or iTerm2 (prompted on first use)

---

## Installation

### Option 1 — Run directly from a repository

```bash
cd /path/to/your/repo
swift run
```

The app detects the working directory as the initial repository and opens in the menu bar. When launched from a terminal it automatically re-launches itself as a detached background process so your shell prompt returns immediately.

### Option 2 — Build the app bundle

```bash
./scripts/build_app.sh
```

This compiles a release build and assembles `dist/GitStatus.app` with a complete `Info.plist`. The app bundle can be double-clicked or opened with `open dist/GitStatus.app`.

### Option 3 — Install the `gitviz` CLI command

```bash
./scripts/install_command.sh
```

This symlinks `bin/gitviz` → `/opt/homebrew/bin/gitviz`. After that, run `gitviz` from any directory to launch the menu bar app monitoring that repo.

The `bin/gitviz` wrapper script:

```bash
#!/bin/zsh
exec "$(dirname "$0")/../dist/GitStatus.app/Contents/MacOS/GitStatus" "$@"
```

---

## Permissions

**Automation (AppleScript)**
Required to query Terminal and iTerm2 for open TTYs. Prompted the first time the discovery service runs. Grant it in **System Settings → Privacy & Security → Automation**. If denied, a warning appears in the menu and only the launch-directory repository is available.

---

## Menu Reference

| Item | Description |
|---|---|
| Status summary | Branch, upstream comparison, file count, +/- lines |
| Repository: `<name>` | Currently monitored repository |
| Last updated: `<time>` | Timestamp of the last successful status refresh |
| **Show Full Diff** | Opens the diff viewer window |
| **Open in Finder** | Reveals the repository root |
| Commit message field | Type a message and press Enter (or click ACP) |
| **ACP** | `git add . && git commit -m "..." && git push` |
| **Pull `<upstream>`** | Pull from the configured upstream branch |
| **Pull `<branch>`** | Pull the current branch from its remote |
| **Repositories** | Submenu listing all discovered repos; click to switch |
| **Refresh Now** (`R`) | Force an immediate re-scan of repos and git status |
| **Quit GitStatus** (`Q`) | Terminate the app |

The menu bar button title is `<branch>` with optional suffixes:
- `*` — working tree has unstaged changes
- `+` — index has staged changes

Example: `main*+` means you're on `main` with both staged and unstaged changes.

---

## Architecture

GitStatus is a Swift Package Manager executable targeting macOS 13+. It uses AppKit directly — no SwiftUI, no Xcode project file.

```
Sources/GitStatus/
├── main.swift                          # NSApplication bootstrap, BackgroundLauncher
├── AppDelegate.swift                   # App lifecycle, wires all services together
├── MenuBarController.swift             # NSStatusItem, NSMenu, all menu item state
├── GitStatusMonitor.swift              # DispatchSource .git watcher + git polling
├── Models/
│   ├── GitStatus.swift                 # Parsed status value type
│   ├── GitDiffSnapshot.swift           # Full diff data for the viewer window
│   └── DiscoveredRepository.swift      # Repo identity (path, name, source labels)
├── Utils/
│   ├── GitCommand.swift                # All git subprocess calls
│   ├── ProcessRunner.swift             # Foundation.Process wrapper
│   ├── BackgroundLauncher.swift        # Detach-from-terminal logic
│   ├── SingleInstanceLock.swift        # File-based lock to prevent duplicate instances
│   ├── GitDiffReportRenderer.swift     # Formats diff snapshot for display
│   └── BackgroundLauncher.swift
├── Services/
│   └── RepositoryDiscoveryService.swift# AppleScript TTY scan + proc_pidinfo CWD lookup
└── UI/
    └── GitDiffWindowController.swift   # Full diff viewer window
```

### Key components

**`AppDelegate`** is the central coordinator. On launch it:
1. Acquires the single-instance lock (exits if already running)
2. Creates `GitStatusMonitor` and `RepositoryDiscoveryService`
3. Resolves the launch directory as an initial fallback repository
4. Wires delegate callbacks between the menu bar controller and both services

**`GitStatusMonitor`** runs on a dedicated `DispatchQueue`. It:
- Resolves the `.git` directory with `git rev-parse --git-dir`
- Installs `DispatchSourceFileSystemObject` watchers on the `.git` directory, `HEAD`, and `index`
- Debounces change events by 150 ms before running a refresh
- Falls back to a 30-second polling timer for cases where file events are missed
- On each refresh, runs `git rev-parse --abbrev-ref HEAD`, `git status --porcelain`, `git diff --numstat --cached`, `git diff --numstat`, and `git rev-list --left-right --count <upstream>...HEAD`
- Publishes a `GitStatus` value to the main actor only when the result differs from the last published value

**`RepositoryDiscoveryService`** polls every 10 seconds. For each running terminal provider (Terminal, iTerm2) it:
1. Runs an AppleScript to collect all open TTY paths
2. For each TTY, runs `ps -t <tty> -o pid=` to get process IDs
3. Uses `proc_pidinfo(PROC_PIDVNODEPATHINFO)` to read each process's current working directory
4. Calls `git rev-parse --show-toplevel` on each CWD to find the repository root
5. Merges results by path, tracking source labels and session counts
6. Sorts by session count (most active repo first), then alphabetically

**`MenuBarController`** owns the `NSStatusItem` and the entire `NSMenu` hierarchy. It implements `NSTextFieldDelegate` for the inline commit message field. All state mutations go through a single `updateRefreshUI()` method that enables/disables items based on current state.

**`GitCommand`** centralizes all subprocess calls through `ProcessRunner` (a thin `Foundation.Process` wrapper). Key operations:
- `run(arguments:in:)` — generic git command runner, throws on non-zero exit
- `repositoryRoot(for:)` — `git -C <path> rev-parse --show-toplevel`
- `diffSnapshot(for:)` — collects porcelain status, shortstat, stat, and full patch for both staged and unstaged changes
- `addCommitPush(message:in:)` — `git add .` → `git commit -m` → `git push origin <branch>`
- `pullUpstream(in:)` / `pullCurrentBranch(in:)` — pull with explicit remote and branch names

**`BackgroundLauncher`** detects whether the process was launched from an interactive shell (by checking `isatty` on stdin/stdout/stderr). If so, it re-launches the same executable with a `--background-launch` flag, redirecting stdio to `/dev/null`, then exits the foreground process. This lets you type `gitviz` in a terminal and get your prompt back immediately.

**`SingleInstanceLock`** uses a file lock (via `flock`) so that running `gitviz` a second time in the same session exits cleanly rather than opening a duplicate menu bar item.

---

## Development

```bash
# Debug build and run (monitors the current directory's repo)
swift run

# Release build
swift build -c release

# Tests
swift test

# Build the app bundle
./scripts/build_app.sh

# Run the built app bundle
./scripts/run_app.sh
```

The package targets Swift 6 language mode. All AppKit and menu bar work is isolated to `@MainActor`; git commands and file-system work run on background `DispatchQueue`s. The `GitStatusMonitor` and `RepositoryDiscoveryService` are marked `@unchecked Sendable` because they manage their own internal synchronization via a serial queue.

### Adding a new git action

1. Add a static method to `GitCommand.swift`
2. Add a menu item and `@objc` action to `MenuBarController.swift`
3. Add a delegate method to `MenuBarControllerDelegate` and implement it in `AppDelegate.swift` using the existing `runGitAction(loadingMessage:action:)` helper

### Adding a new terminal provider

Add a new case to the `TerminalProvider` enum in `RepositoryDiscoveryService.swift` with the bundle identifier and the AppleScript lines needed to enumerate TTY paths.
