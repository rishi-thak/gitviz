#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build_app.sh"
open "$ROOT_DIR/dist/GitStatus.app"
