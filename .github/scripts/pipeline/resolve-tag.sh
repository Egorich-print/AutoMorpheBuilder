#!/usr/bin/env bash
# resolve-tag.sh — resolve the latest release tag for a GitHub repo given a branch
#
# Usage:
#   source .github/scripts/pipeline/resolve-tag.sh
#   tag="$(resolve_release_tag "owner/repo" "branch")"
#
# Requires GH_TOKEN in environment.
#
# Exit codes of resolve_release_tag:
#   0  a tag was resolved (printed on stdout)
#   1  the repo is reachable but no release tag could be resolved
#   2  the repo itself is unusable — blocked, deleted or renamed
#
# The function returns instead of calling `exit`, so a caller can decide
# per repo whether an unresolvable tag is fatal (the CLI tag is) or
# merely excludes the apps that depend on it (a patch repo is).

# repo_access_state <owner/repo>
#   Prints one of: ok | blocked | missing | unknown
#
# A patch repo can disappear from under the pipeline in two very
# different ways: GitHub blocks it (ToS violation -> HTTP 403, the slug
# still resolves in the owner listing) or it is deleted/renamed (404).
# Every `gh release ...` call against such a repo returns nothing, which
# used to look identical to "the repo has no releases yet" — the daily
# build then failed with "No stable release found" for three weeks
# before the real cause (a blocked upstream) was noticed. Distinguishing
# the two states turns that into a one-line diagnosis.
#
# Only called after a resolution failure, so the happy path stays free
# of extra API traffic.
repo_access_state() {
  local repo="$1"
  if ! command -v curl >/dev/null 2>&1; then
    printf 'unknown'
    return 0
  fi
  local body
  body="$(curl -s --connect-timeout 10 --max-time 30 \
    -H "Authorization: Bearer ${GH_TOKEN:-}" \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${repo}" 2>/dev/null || true)"
  # A blocked repository answers with an explicit block object — that is
  # the one unambiguous "this upstream is gone" signal GitHub gives, and
  # it is what a terms-of-service violation looks like. Match the
  # message, not the JSON layout: the API pretty-prints its errors.
  case "$body" in
    *'Repository access blocked'*) printf 'blocked'; return 0 ;;
    *'Not Found'*) printf 'missing'; return 0 ;;
  esac
  printf 'unknown'
}

resolve_release_tag() {
  local repo="$1"
  local branch="$2"
  local stable_tag selected_tag

  # Prefer the latest non-prerelease release (gh release view's default).
  # Fall back to the latest release of any kind if the repo only ships
  # pre-releases/drafts (e.g. an in-progress dev tag) so the build can
  # still proceed. Redirect 2>/dev/null so "release not found" can't
  # leak into the captured stdout on older gh versions.
  stable_tag="$(gh release view --repo "$repo" --json tagName -q .tagName 2>/dev/null || true)"
  if [ -z "$stable_tag" ]; then
    log_warn "No stable release found for ${repo}; falling back to latest release (pre-release/draft)."
    stable_tag="$(gh release list --repo "$repo" --limit 1 --exclude-drafts --exclude-pre-releases --json tagName -q '.[0].tagName // empty' 2>/dev/null || true)"
    if [ -z "$stable_tag" ]; then
      stable_tag="$(gh release list --repo "$repo" --limit 1 --exclude-drafts --json tagName -q '.[0].tagName // empty' 2>/dev/null || true)"
    fi
  fi

  if [ "$branch" = "main" ]; then
    selected_tag="$stable_tag"
  else
    selected_tag="$(
      gh api "repos/${repo}/releases?per_page=100" --jq '
        [ .[]
          | select(
              (.draft != true)
              and (
              ((.target_commitish // "" | ascii_downcase) == "dev")
              or (.prerelease == true)
              or ((.tag_name // "" | ascii_downcase | test("(^|[-_.])(dev|beta|alpha|rc)")))
              )
            )
        ][0].tag_name // empty
      ' || true
    )"
    if [ -z "$selected_tag" ]; then
      log_warn "No dev-style release found for ${repo}; falling back to latest."
      selected_tag="$stable_tag"
    fi
  fi

  if [ -z "$selected_tag" ]; then
    # Say *why* the repo gave nothing. A repo that GitHub blocked (a
    # terms-of-service violation answers every call with 403) or that
    # was deleted/renamed (404) looks exactly like "no releases yet"
    # from the release API alone, and the two need completely different
    # fixes. Diagnose it here so the log names the real cause.
    local repo_state
    repo_state="$(repo_access_state "$repo")"
    if [ "$repo_state" = "blocked" ]; then
      log_error "Patch repo ${repo} is blocked by GitHub (terms-of-service violation); its releases cannot be read."
      return 2
    fi
    if [ "$repo_state" = "missing" ]; then
      log_error "Patch repo ${repo} does not exist (deleted or renamed)."
      return 2
    fi
    log_error "Could not resolve release tag for ${repo} (branch=${branch})."
    return 1
  fi

  # Strip any CR/LF the upstream release API might have returned.
  # resolve_release_tag's output is written to $GITHUB_OUTPUT via
  # KEY=VALUE lines; a newline in the tag would inject extra keys.
  selected_tag="${selected_tag//$'\r'/}"
  selected_tag="${selected_tag//$'\n'/}"
  echo "$selected_tag"
}
