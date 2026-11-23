#!/usr/bin/env bash
#
# scripts/gate.sh — the repository's own CI gate.
#
# Jenkins (and any other CI that honours the conventional gate-script
# names) runs this file instead of guessing a generic build for the
# project type. The point is that the *repository* owns its checks:
# this script is the same chain `.github/workflows/ci.yml` runs, so a
# green Jenkins build means the same thing as a green GitHub Actions
# build.
#
# See AGENTS.md → "Required Validation" for the canonical list.
#
# Usage:
#   ./scripts/gate.sh            # full gate
#   SKIP_TESTS=1 ./scripts/gate.sh   # lint + config validation only
#
# Exit code: 0 when every check passed, non-zero otherwise.

set -Eeuo pipefail

cd "$(dirname "$0")/.."

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'
[ -t 1 ] || { RED=''; GREEN=''; YELLOW=''; RESET=''; }

step() { printf '\n%s==> %s%s\n' "$GREEN" "$*" "$RESET"; }
note() { printf '%s    %s%s\n' "$YELLOW" "$*" "$RESET"; }
die()  { printf '\n%sFAIL: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed."
}

# --- the chain ci.yml runs -------------------------------------------------

require node
require npm

step 'Install dependencies'
npm ci

step 'Lint'
npm run lint

if [ "${SKIP_TESTS:-0}" = "1" ]; then
  note 'SKIP_TESTS=1 — skipping the test suite.'
else
  step 'Test'
  npm test
fi

step 'Validate config.json shape'
npm run validate:config

step 'Verify README tables match config.json'
npm run check:readme

step 'Validate contributor instructions'
npm run validate:agent-docs

# --- shell / workflow linting ----------------------------------------------
#
# Both tools are optional: a runner without them still gets a complete
# gate, it just cannot check the shell scripts and the workflow YAML.

if command -v shellcheck >/dev/null 2>&1; then
  step 'shellcheck'
  # Same invocation as ci.yml: -x follows the sourced libraries,
  # -P SCRIPTDIR resolves the `source` directives relative to the script.
  shellcheck -x -P SCRIPTDIR .github/scripts/pipeline/*.sh .github/scripts/pipeline/lib/*.sh scripts/*.sh
else
  note 'shellcheck not installed — skipping the shell lint (ci.yml installs it).'
fi

if command -v actionlint >/dev/null 2>&1; then
  step 'actionlint'
  actionlint .github/workflows/*.yml
else
  note 'actionlint not installed — skipping the workflow lint (ci.yml installs it).'
fi

printf '\n%sAll checks passed.%s\n' "$GREEN" "$RESET"
