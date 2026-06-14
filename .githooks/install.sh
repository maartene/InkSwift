#!/bin/sh
# Activate the versioned InkSwift git hooks for this clone.
# Idempotent: safe to run repeatedly.
set -e

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit

echo "✓ core.hooksPath set to .githooks"
echo "✓ pre-commit gate active (SwiftLint + swift test)."
echo "  Bypass once with: git commit --no-verify"
