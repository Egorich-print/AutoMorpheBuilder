# AGENTS.md — AutoMorpheBuilder

AutoMorpheBuilder is a GitHub Actions pipeline that builds signed, patched Android APKs with [Morphe](https://github.com/MorpheApp/morphe-patches) patches. **The workflow is the product** — there is no app to run locally. This file is a guide for AI agents and human contributors working in the repo.

## Sources of Truth

Every authoritative file in the repo, with its role. When information conflicts, the file listed below wins; this document only summarises them.

- `config.json` — application definitions and patch repositories.
- `patches.json` — per-application patch selection (repo-keyed format, see `docs/configuration.md`).
- `.github/workflows/morphe-build.yml` — main build orchestration (daily + `workflow_dispatch`).
- `.github/workflows/update-patches.yml` — patch metadata updates from upstream patch repos.
- `.github/workflows/ci.yml` — continuous integration (PR + main gate).
- `.github/workflows/codeql.yml` — security analysis.
- `.github/dependabot.yml` groups CodeQL action steps so `init` and `analyze` upgrade together (mismatched versions fail analysis).
- `README.md` — project overview.
- `SETUP.md` — fork and signing setup walkthrough.
- `CONTRIBUTING.md`, `SECURITY.md` — community files (contribution guide, vulnerability disclosure).
- `docs/configuration.md` — `config.json` field reference and "adding a new app" procedure.
- `docs/architecture.md` — pipeline architecture, job graph, Mermaid diagram.
- `docs/troubleshooting.md` — common failures, symptoms, causes, fixes.
- `docs/release-process.md` — release tagging, naming, and pruning.
- `.github/ISSUE_TEMPLATE/` — bug report, app request, download-resolver-failure templates + `config.yml`.
- `.github/pull_request_template.md` — PR description template.
- `.github/CODEOWNERS` — required reviewers per path.

## Generated and Managed Files

The repo mixes hand-curated and workflow-generated content. Treat the categories below as a contract — do not move a file across categories without a PR that explains why.

**User-managed** (edit freely; preserved across workflow runs):

- `config.json` — the source of truth for `patch_repos`, `cli`, `preferred_arch`, `auto_update_urls`.
- `patches.json` — the Boolean values you set per patch. New upstream patches default to `true` on first sync; your existing toggles are preserved.
- `docs/`, `README.md`, `SETUP.md`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md` — human-authored documentation.
- Tests and fixtures under `.github/scripts/__tests__/`.

**Workflow-managed** (do not hand-edit; the workflow rewrites them):

- `patches.json` keys for newly discovered upstream patches (added by `update-patches.yml`; your existing values are preserved on every sync).
- `config.json` `download_urls` cache — written by `pre_download_apks.sh` when `auto_update_urls` is `true`. Clear `~/.cache/auto-morphe-builder/urls/` to force re-resolution.
- Build artifacts under `apps/`, `tools/`, `out/` — gitignored, produced by the workflow.
- `tree -a -I '.git|node_modules|coverage|dist|build|tools|apps' -L 3` shows the full tree.

**Rule:** when updating `patches.json`, preserve existing user-selected Boolean values; new upstream patches default to `true`.

## Repository Layout (conceptual)

- **Workflows**: `.github/workflows/morphe-build.yml`, `update-patches.yml`, `ci.yml`, `codeql.yml` — orchestration only.
- **Scripts (Node.js)**: `.github/scripts/*.js` — downloaders, validators, release helpers, installer scripts.
- **Scripts (shell pipeline)**: `.github/scripts/pipeline/*.sh` plus shared helpers in `.github/scripts/pipeline/lib/`. Each `<step>.sh` corresponds to one workflow step.
- **Scripts (CLI orchestrators)**: `scripts/*.js` — thin entry points that wire `node_modules` (ajv etc.) into the pure logic in `.github/scripts/`. `scripts/generate-readme-tables.js` regenerates the "Tested apps" / "Releases & Obtainium" tables in `README.md` from `config.json` `patch_repos`.
- **Gate script**: `scripts/gate.sh` — the repository's own CI gate (lint → test → validate:config → check:readme → validate:agent-docs → shellcheck → actionlint). It exists so that an external CI runner runs *these* checks instead of guessing a generic build for the project type. `scripts/gate.sh` is the same chain `.github/workflows/ci.yml` runs.
- **Tests**: `.github/scripts/__tests__/*.test.js` — Jest unit tests for pure helpers and CLI wrappers.
- **Config**: `config.json`, `patches.json`, `eslint.config.js` (lints `.github/scripts/**/*.js` only).
- **Docs**: `docs/{configuration,architecture,troubleshooting,release-process}.md` plus `README.md`, `SETUP.md`, `AGENTS.md`.
- **Community**: `CONTRIBUTING.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`, `.github/CODEOWNERS`.

## Change Rules

1. Keep workflow YAML focused on orchestration; move logic into `.github/scripts/*.js` or `.github/scripts/pipeline/*.sh`.
2. Put reusable logic in JavaScript or shell modules — never inline duplicated shell in workflow YAML.
3. Add or update tests for every behavioural change. Behavioural logic must live behind a pure, exported function so Jest can exercise it without shelling out.
4. Add fixtures (sample `patches-list.json`, APKMirror HTML, protobuf payloads) when handling a new upstream response format.
5. Do not log secrets, passwords, keystore contents, or `Authorization:` headers. Use `set +x` / `::add-mask::` / `keytool -storepass:env` as appropriate.
6. Do not weaken APK, package-name, version, checksum, or signature validation. Adding a "skip the version check" or "trust any cert" path is a hard fail.
7. Preserve backward compatibility for existing `config.json` files unless a breaking change is explicitly documented in the PR description and `docs/configuration.md`.
8. Update related documentation in the same PR. Adding a workflow step, env var, or config field without updating `docs/` and `AGENTS.md` is incomplete.
9. Run all required validation commands before committing (see [Next](#required-validation)).

## Required Validation

Run these before every commit. `npm run check` runs the full chain (lint + test + validate:config + validate:agent-docs + check:readme).

```bash
npm ci
npm run lint
npm test
npm run validate:config
npm run check:readme        # regenerates README tables in-memory and diffs; --check-style
```

`npm run generate:readme` (no flag) writes the regenerated tables back to `README.md` — run this after any change to `config.json` `patch_repos` so the "Tested apps" / "Releases & Obtainium" tables stay in sync. `update-patches.yml` does this automatically on push to main, alongside the existing patches.json sync.

Shell scripts use `shellcheck .github/scripts/pipeline/*.sh .github/scripts/pipeline/lib/*.sh`; workflow YAML uses `actionlint .github/workflows/*.yml`. CI runs `node .github/scripts/validate-config.js` directly (it is not on `npm run` yet); the JSON config validator catches typos and missing required keys before merge.

`scripts/gate.sh` runs exactly this chain and nothing else — an external CI runner that honours the conventional gate-script names will call it. `SKIP_TESTS=1 scripts/gate.sh` skips the test suite.

## Repo quirks (not obvious from filenames)

- **`morphe-build.yml` runs against the default branch on its `schedule` trigger.** The daily `cron` (05:15 UTC) executes against whichever branch GitHub considers default — currently `main`. A change merged only to `dev` will NOT be picked up by the schedule; it is invisible until `dev` is fast-forwarded or merged into `main`. When a hotfix lands on `dev`, merge it into `main` (or open a `dev` → `main` PR) so the next scheduled build sees it. `workflow_dispatch` lets you pick the ref explicitly, so it can serve as a manual backstop for testing without waiting for the merge.
- `morphe-desktop.jar` is **never** cached. `actions/cache@v5` only saves on miss, so caching the jar would silently put a stale jar back into `tools/`. `download_morphe_tools.sh` and `fetch_morphe_tools.sh` both `rm -f` and re-download on every run. See `docs/troubleshooting.md` → "java.lang.NoSuchMethodError" for the failure mode this prevents.
- `morphe-desktop.jar` has two layers of integrity checks, in order:
  1. `unzip -p META-INF/MANIFEST.MF | grep Implementation-Version` — strips a trailing `\r` before comparing against `CLI_TAG`, because the upstream JAR's MANIFEST.MF uses CRLF endings and would otherwise warn "version mismatch" even when both sides match.
  2. SHA-256 against the GitHub release-API per-asset digest (`gh_asset_sha256`). A byte-level mismatch against the API digest is a hard fail (corruption or republish).
  3. If the pin row in `checksums/tools.sha256` (with a `# vX.Y.Z` version annotation) names a *different* CLI tag than the one we're downloading, the SHA disagreement is a CLI bump, not a tamper signal — the verify scripts log a `TODO(refresh-pin-morphe-desktop)` line and continue. Without the version annotation, any disagreement stays a hard fail so a malformed manifest cannot silently disable the tripwire.
  See `docs/checksums.md` for the full contract.
- Per-repo `*.mpp` patches archives ARE SHA-256-verified in `fetch_morphe_tools.sh` against the per-asset digest served by the GitHub release API (`gh_asset_sha256`). A stale cache entry (e.g. one left over from before fd537df removed `restore-keys: morphe-patches-<slug>-`) fails the SHA check, gets re-downloaded, and the next `actions/cache` save replaces it with the correct bytes — no manual `gh cache delete` required. See `docs/troubleshooting.md` → "Build job silently skips patches" for the symptom and recovery.
- `apkeep` installer verifies SHA-256; `aapt` and `playwright` installers do not (PR 6). The previous `install_bouncycastle.sh` (BouncyCastle for keystore conversion) was deleted when morphe-desktop's `patch --keystore` flags made the conversion redundant.
- `verifyUrl()` in `.github/scripts/unified-downloader.js` (the cache-URL HEAD probe) sanitises the URL through `new URL()` and requires `protocol === 'https:'` before issuing the HEAD request. The URL that reaches `fetch()` is the WHATWG-canonicalised form, not the raw input. The cache file itself is written only by `saveCachedUrl()` after a successful resolver round-trip (or by `update-download-urls.js` from the user's own `patches.json`), so the URL string flowing into `fetch()` is operationally trusted — but the file → fetch edge is real taint and the protocol gate breaks the flow that CodeQL's `js/file-access-to-http` query tracks (alert #37). Tests in `__tests__/unified-downloader-timers.test.js` cover the four cases: http://, file://, malformed, and the canonical https: accept path.
- Direct APK transfers in `downloadWithUrl()` parse and require credential-free HTTPS URLs before invoking curl, terminate curl options with `--`, and restrict redirects to HTTPS. See `docs/checksums.md` for the URL policy and fixture-test isolation.
- Signing has **no** `--unsigned` fallback. morphe-desktop's `patch` always signs when `--keystore` is passed; a bad password or invalid keystore aborts the workflow loudly rather than producing an unsigned APK. The previous `build` ↔ `sign` trust boundary was dissolved (see `docs/architecture.md` → "Signing model" for the implications).
- morphe-desktop v1.14.0 hardcodes `--keystore-entry-password` and `--keystore-entry-alias` defaults to `"Morphe"` (legacy bundled-keystore alias, see `MorpheApp/morphe-desktop` `PatchCommand.kt:215`/`221` + `PatchEngine.kt:64`/`65`). They do NOT inherit from `--keystore-password` and do NOT auto-pick the keystore's first alias — omitting either flag silently tries the literal password `"Morphe"` and fails with `BadPaddingException`. `patch_apk.sh` always passes both explicitly (alias detected via `keytool -list` when `KEY_ALIAS` is unset; entry password defaults to `KEYSTORE_PASSWORD` when `KEY_PASSWORD` is unset). If morphe-desktop later inherits from `--keystore-password` or auto-picks the first alias, the script can be simplified.
- The downloader saves XAPK/APKM/APKS bundles with a `.apk` extension. `detectApkShape` in `apk-selection.js` inspects zip contents to recognise bundles — required because APKMirror often serves bundles without preserving the extension.
- The `aapt` version check is skipped for split packages (the outer zip-of-zips is not a valid APK); the post-merge step verifies the inner `base.apk`.
- `pre_download_apks.sh` runs apps in parallel via `&` + `wait`. Each app's `.mpp` is passed directly to `morphe-desktop list-versions` (no shared-file race).
- `check_existing_releases.sh` is **fail-open**: if `morphe-desktop list-versions` returns nothing or `gh release view` errors, the app is kept in the matrix with a `::warning::`. The build never silently skips an app we couldn't version-check.
- The `compat-probe` step (in the `check-versions` job) runs `list-versions` per app and surfaces `NoSuchMethodError` / `NoClassDefFoundError` at the cheapest step rather than 30 minutes into the matrix.
- `update-patches.yml`'s push-trigger gate (`scripts/detect-new-repos.js`) opens on **either** a brand-new patch repo in `config.json` (case a) **or** an existing app whose `patch_repos[*].repo` changed (case b — relocated). Case (b) is the bit that catches "I moved sofascore to a different patches repo" — without it, the sync was silently skipped because the destination repo already existed in `patches.json` (carrying unrelated apps), and on the next dispatch the jq merge would have wiped the user's per-patch toggles for the moved app. Both `detectChanges` (`scripts/detect-new-repos.js`) and the merge used by `sync-patches.sh` (`scripts/merge-patches.js`) are pure functions with unit tests in `.github/scripts/__tests__/{detect-new-repos,merge-patches}.test.js`. The merge prefers the destination repo's section for an app but **falls back** to the same app's entry under any other repo key in `patches.json` so explicit `false` toggles like `Disable telemetry: false` survive a repo move.
- The Playwright cache (`~/.cache/ms-playwright`) is restored by `actions/cache` keyed on `runner.os` + hash(`package.json`, `package-lock.json`); when Playwright is upgraded, the primary key misses and the `restore-keys:` prefix fallback brings back an older partial archive that may match one browser (e.g. `chromium-1208`) without matching another (e.g. `chromium_headless_shell-1234`). The previous `find -name 'chrome'` heuristic in `install_playwright.sh` incorrectly reported "all installed" in that case, the install was skipped, the smoke test failed, and **mimo** was the only app that surfaced as a hard failure (every other app's APK download happens to succeed without Playwright). `scripts/check-playwright-browsers.js` (`checkPlaywrightBrowsers`, unit-tested in `.github/scripts/__tests__/check-playwright-browsers.test.js`) is the revision-aware check: it reads `playwright-core/browsers.json` and verifies `INSTALLATION_COMPLETE` at `<cacheDir>/<browser-name-with-underscores>-<expected-revision>/` for each browser. `install_playwright.sh` always runs `install-playwright-browsers.js` regardless of the helper's verdict — the per-browser marker check inside `install-playwright-browsers.js` makes the no-op case free, and unconditionally running it is the only safe posture against stale restore-keys hits.
- **One dead upstream must not take the whole build down.** A patch repo can disappear or stop shipping an app without warning: GitHub blocked `hoo-dles/morphe-patches` for a terms-of-service violation on 2026-11-18, and `RookieEnough/De-Vanced` dropped `tv.twitch.android.app` from its `patches-list.json` in v1.6.3. Before the fix, either event aborted the `check-versions` job and **no app shipped at all** — the daily build stayed red for three weeks. Now:
  - `resolve_release_tag` returns instead of exiting, and reports *why* it failed: `repo_access_state` distinguishes a repo GitHub **blocked** (the API answers with a `Repository access blocked` body) from one that was **deleted/renamed** (`Not Found`) from one that simply has no release yet. Exit code 2 means "repo unusable", 1 means "no tag".
  - `check_versions.sh` turns an unusable repo into an **exclusion**: the apps on that repo leave the matrix (loud `::warning::` + `excluded-apps` output) and every other app still builds. The CLI tag is *not* per-app, so a failure there stays fatal.
  - `preflight-apps.js` does the same for an app whose package the upstream no longer lists — but only for apps the maintainer already configured (a non-empty patch selection in `patches.json`). An app without such a selection was never verified and is most likely a **typo in `config.json`**, so it stays a hard error. If *every* app ends up excluded, the build fails: shipping nothing while reporting success is not an option.
  - The exclusion list travels `check-versions` → `preflight` → `filter` (`EXCLUDED_APPS` env, `excluded-apps` output) and `build-plan.js`'s `buildMatrix(config, versions, excludedApps)` drops the excluded apps so they cannot re-enter the matrix.
- **`config.json` `pin_patch_tag` is the upstream-regression brake.** When an upstream patch release drops an app or ships something the CLI cannot run, pinning that app to the last known-good tag (`"pin_patch_tag": "v1.6.2"`) holds the matrix without touching the other apps. `check_versions.sh` skips tag resolution entirely for a pinned app, and `sync-patches.sh` pins it the same way.
- **APKMirror serves a Cloudflare anti-bot challenge to headless browsers.** Visiting `/all-versions/` triggers it, and it poisons the *next* navigation in the same browser session. `page.goto(..., {waitUntil: 'domcontentloaded'})` resolves on the challenge document, so scraping immediately yields a DOM with zero `.table-row` elements and `selectVariant` reports "No matching variant found on APKMirror. Available: none" — which reads like "this app has no arm64 build". The scraper therefore waits for the element it actually needs (`waitForPageContent`) after every navigation; the challenge solves itself in the browser and the real DOM replaces it.
- **`APKMIRROR_API_USER` / `APKMIRROR_API_PASS` are not set on this repository.** The downloader's fallback chain is apkeep → apkmirror-api → apkmirror (Playwright). Without the API credentials the second rung is skipped, and the first one fails for versions APKPure has already dropped (it no longer serves `com.reddit.frontpage@2026.40.0`). The Playwright path then carries the whole download, and it is exposed to APKMirror's bot protection.

## Local environment

Node.js 24 (matches `actions/setup-node@v6`; `package.json` declares `"engines": { "node": ">=24" }`). Java 21 (matches `actions/setup-java@v6`; required by `morphe-desktop` ≥ 1.12.0). The CI workflow installs `zip` via `apt-get` because the apk-selection / apk-abi-validator test fixtures shell out to `zip` to build fake APKs; without it several tests skip with "no zip" warnings instead of actually exercising the path-stripping bug fix. Tests use Jest only; ESLint is scoped to `.github/scripts/**/*.js` via `eslint.config.js`. Shell pipeline linting (`shellcheck`) is not part of `npm run lint`.

**Bash 4+ is required to run the pipeline scripts locally.** `check_versions.sh` and the other shell entry points use `declare -A` and `mapfile`. macOS still ships bash 3.2, so the shell-driven test cases skip there (they run on CI and on the Jenkins agent, which use bash 5). `shellcheck` and `actionlint` are optional for `scripts/gate.sh` — it warns and skips them when they are not installed.