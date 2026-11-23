'use strict';

const crypto = require('node:crypto');

// App-keyed maps preserve independent selectors. Repo-keyed maps remain
// accepted for local callers using the older interface.
function patchTag(appId, entry, versions) {
  return entry.pin_patch_tag || versions[appId] || versions[entry.repo] || '';
}

function patchSlug(appId, entry, versions) {
  const repoSlug = entry.repo.replace(/\//g, '-');
  if (!Object.hasOwn(versions, appId)) return repoSlug;
  const digest = crypto.createHash('sha256').update(`${entry.repo}\n${patchTag(appId, entry, versions)}`).digest('hex').slice(0, 16);
  return `${repoSlug}-${digest}`;
}

function buildMatrix(config, versions, excludedApps = []) {
  const excluded = new Set(excludedApps);
  return Object.entries(config.patch_repos)
    .filter(([appId]) => !excluded.has(appId))
    .map(([appId, entry]) => ({
      name: entry.name,
      appId,
      patchRepo: entry.repo,
      patchBranch: (entry.branch || 'main').toLowerCase(),
      patchTag: patchTag(appId, entry, versions),
      patchSlug: patchSlug(appId, entry, versions),
    }));
}

function supportedVersions(stdout) {
  return [...new Set(stdout.match(/\d+(?:\.\d+)+/g) || [])]
    .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
}

if (require.main === module) {
  const fs = require('node:fs');
  const config = JSON.parse(fs.readFileSync(process.env.CONFIG_FILE || 'config.json', 'utf8'));
  // Apps excluded upstream (unusable patch repo, package no longer
  // listed) are dropped from the matrix so one broken app cannot take
  // the whole daily build down with it.
  let excludedApps;
  try {
    excludedApps = JSON.parse(process.env.EXCLUDED_APPS || '[]');
  } catch {
    excludedApps = [];
  }
  console.log(JSON.stringify(buildMatrix(config, JSON.parse(process.env.REPO_VERSIONS || '{}'), excludedApps)));
}

module.exports = { patchTag, patchSlug, buildMatrix, supportedVersions };
