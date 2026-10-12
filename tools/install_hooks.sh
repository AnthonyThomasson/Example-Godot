#!/usr/bin/env bash
# Point git at the tracked hooks in .githooks/ (the pre-commit game tests). Run once per clone.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "git hooks enabled (core.hooksPath=.githooks)"
