# Repository Guidelines

## Project Structure & Module Organization
`GitStatus` is a Swift Package Manager executable targeting macOS 13+ with AppKit. Main app code lives in `Sources/GitStatus/`.

- `main.swift`: launches the accessory-style menu bar app.
- `AppDelegate.swift`: app lifecycle and monitor wiring.
- `MenuBarController.swift`: `NSStatusBar` button and menu behavior.
- `GitStatusMonitor.swift`: git polling, file watching, and refresh logic.
- `Models/`: shared data models such as `GitStatus`.
- `Utils/`: small helpers like the `Process`-based git command wrapper.
- `Tests/GitStatusTests/`: Swift Testing coverage for app logic that can be validated without full UI automation.

## Build, Test, and Development Commands
- `swift build`: compile the package in debug mode.
- `swift test`: run the Swift Testing suite.
- `swift run`: launch the menu bar app from the current repository.
- `./scripts/run_app.sh`: build the app bundle and open it.
- `./scripts/install_command.sh`: install the `gitviz` shell command into `/opt/homebrew/bin`.

Run `swift run` from the git repository you want to monitor, since the app resolves the working directory as the target repo.

## Coding Style & Naming Conventions
Use standard Swift style: 4-space indentation, no tabs, and one type per file where practical. Prefer `UpperCamelCase` for types (`MenuBarController`) and `lowerCamelCase` for methods and properties (`showLoadingState`). Keep AppKit work on the main actor and isolate git/file-system work on background queues.

There is no formatter or linter configured yet. Keep imports minimal, favor small focused types, and avoid third-party dependencies unless there is a clear need.

## Testing Guidelines
Tests use Apple’s `Testing` framework, not XCTest. Place tests in `Tests/GitStatusTests/` and name them after the behavior they verify, for example `menuBarFormattingReflectsGitState`. Add tests for parsing, title formatting, and command wrappers when logic changes. Run `swift test` before opening a PR.

## Commit & Pull Request Guidelines
Git history currently starts with a single `init` commit, so no strict convention is established yet. Use short, imperative commit messages such as `Add diff menu action stub` or `Fix watcher refresh debounce`.

For pull requests, include:
- a concise summary of the change
- any manual verification steps (`swift build`, `swift test`, `swift run`)
- screenshots or a short screen recording for visible menu bar/UI changes
- linked issues or follow-up work when relevant

## Security & Configuration Tips
Do not hardcode repository-specific paths or shell assumptions beyond standard macOS tools. Keep all git execution routed through `Utils/GitCommand.swift` so command behavior stays centralized and reviewable.
