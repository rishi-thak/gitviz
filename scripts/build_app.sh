#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GitStatus"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/$APP_NAME"
BUILD_LOG="$(mktemp -t gitviz-build.XXXXXX.log)"
START_TIME="${EPOCHSECONDS:-$(date +%s)}"

if [[ -t 1 ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_MUTED=$'\033[38;5;245m'
  COLOR_ACCENT=$'\033[38;5;45m'
  COLOR_SUCCESS=$'\033[38;5;42m'
  COLOR_ERROR=$'\033[38;5;196m'
  COLOR_WARN=$'\033[38;5;220m'
  COLOR_BOLD=$'\033[1m'
  COLOR_DIM=$'\033[2m'
else
  COLOR_RESET=''
  COLOR_MUTED=''
  COLOR_ACCENT=''
  COLOR_SUCCESS=''
  COLOR_ERROR=''
  COLOR_WARN=''
  COLOR_BOLD=''
  COLOR_DIM=''
fi

cleanup() {
  rm -f "$BUILD_LOG"
}

trap cleanup EXIT

print_line() {
  printf '%s\n' "$1"
}

print_step() {
  printf '%s%s›%s %s\n' "$COLOR_ACCENT" "$COLOR_BOLD" "$COLOR_RESET" "$1"
}

print_ok() {
  printf '%s%s✓%s %s\n' "$COLOR_SUCCESS" "$COLOR_BOLD" "$COLOR_RESET" "$1"
}

print_fail() {
  printf '%s%s✕%s %s\n' "$COLOR_ERROR" "$COLOR_BOLD" "$COLOR_RESET" "$1"
}

print_note() {
  printf '%s%s%s\n' "$COLOR_MUTED" "$1" "$COLOR_RESET"
}

print_header() {
  print_line "${COLOR_BOLD}${COLOR_ACCENT}gitviz build${COLOR_RESET}"
  print_note "Packaging the menu bar app for launch from the CLI."
  print_line ""
}

print_summary() {
  local elapsed end_time
  end_time="${EPOCHSECONDS:-$(date +%s)}"
  elapsed=$(( end_time - START_TIME ))

  print_line ""
  print_ok "Build ready"
  print_note "App bundle  $APP_DIR"
  print_note "Executable  $EXECUTABLE_PATH"
  print_note "Elapsed     ${elapsed}s"
}

print_header()

mkdir -p "$ROOT_DIR/dist"

print_step "Compiling release build"
if swift build -c release --package-path "$ROOT_DIR" >"$BUILD_LOG" 2>&1; then
  print_ok "Release build compiled"
else
  print_fail "Release build failed"
  print_line ""
  print_note "SwiftPM output:"
  cat "$BUILD_LOG"
  exit 1
fi

print_step "Assembling app bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

/usr/bin/plutil -create xml1 "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.gitviz.GitStatus" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string GitStatus needs Automation access to inspect Terminal and iTerm sessions for active repositories." "$APP_DIR/Contents/Info.plist"

print_ok "App bundle assembled"
print_summary
