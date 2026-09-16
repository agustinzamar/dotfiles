#!/usr/bin/env zsh
# SketchyBar click handler: focus a native macOS Space by 1-based position.
#
# Delegates to the shared Tinycast-driven walker, which switches Spaces through
# Tinycast's own SpaceSwitcher (no Mission Control animation). The previous
# version synthesized ctrl+left/right, but macOS ignores synthesized events for
# its own Space shortcuts, so it never actually switched anything.
#
# Usage: focus-native-space.sh <position>
set -uo pipefail

target="${1:-}"
[[ "$target" =~ ^[1-9][0-9]*$ ]] || exit 0

script_dir="$(cd "$(dirname "${(%):-%x}")" && pwd -P)"
walker="$script_dir/../../tinycast/lib/go-to-native-space.sh"

[[ -x "$walker" ]] || exit 1
exec "$walker" "$target"
