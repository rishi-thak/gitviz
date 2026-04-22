#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_PATH="/opt/homebrew/bin/gitviz"
SOURCE_PATH="$ROOT_DIR/bin/gitviz"

mkdir -p "$(dirname "$TARGET_PATH")"
ln -sf "$SOURCE_PATH" "$TARGET_PATH"

echo "Installed gitviz -> $SOURCE_PATH"
