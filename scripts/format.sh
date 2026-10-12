#!/usr/bin/env bash

set -euo pipefail

is_installed() {
	[[ -x $(command -v "$1") ]]
}

echo "Formatting $PWD"

ROOT=$(git rev-parse --show-toplevel)
readonly ROOT
cd -- "$ROOT" || exit 1

readonly formatter=stylua
if ! is_installed "$formatter"; then
	echo "command not found: $formatter"
	exit 1
fi

# Pass --check to report formatting differences without changing files.
"$formatter" --config-path "$ROOT/.stylua.toml" --verify "$@" "$ROOT/tests" "$ROOT/mpvacious"
