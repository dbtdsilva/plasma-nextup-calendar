# Manual Release Workflow — Design

**Date:** 2026-06-17
**Status:** Approved
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

Give the repo a one-click release process: a manually-triggered GitHub Actions
workflow that bumps the widget version, tags it, and publishes a GitHub Release
with an installable `.plasmoid` artifact. Modeled on the money-nest release
workflow (manual `workflow_dispatch`, human-supplied version/title/notes →
bump → tag → `softprops/action-gh-release`), with money-nest's app-specific
stages (Expo/EAS/OTA, Docker, staging→production promotion, milestone sweep)
dropped because they do not apply to a Plasma widget.

This is the "manual" release style, deliberately **not** semantic-release: the
human chooses the version and writes the notes. (The repo memory note about
semantic-release "coming later" is unchanged; this is the interim, human-driven
process.)

## Release style chosen

money-nest-style **manual** release. Confirmed decisions:

- Trigger: `workflow_dispatch` you run from the Actions tab.
- Version is typed by hand (no derivation from commits).
- Tag format: bare `X.Y.Z` (no `v` prefix), matching money-nest.
- Bump commit authored by `github-actions[bot]` (CI convention, as money-nest).
- The Release attaches a built `.plasmoid` artifact.
- No milestone sweep (this repo doesn't use issues/milestones).
- README gets a dynamic release badge (auto-updating; nothing for the workflow
  to maintain).

## Component: `.github/workflows/release.yml`

This is the repo's first workflow (no `.github/` exists yet).

```yaml
name: Release
on:
  workflow_dispatch:
    inputs:
      version:  { description: "Version to release (e.g. 0.2.0)", required: true, type: string }
      title:    { description: "Release title (e.g. Filters & alerts)", required: true, type: string }
      notes:    { description: "Release notes (markdown)", required: true, type: string }
permissions:
  contents: write
concurrency:
  group: release
  cancel-in-progress: false
```

Single `release` job on `ubuntu-latest`. Every shell/script step that references
`$VERSION` declares `env: { VERSION: ${{ inputs.version }} }` (never interpolating
the input directly into the script body, to avoid shell injection from the free-
text input). Steps, in order:

1. **Checkout** — `actions/checkout@v6` (default `persist-credentials: true`, so
   the later `git push` authenticates with `GITHUB_TOKEN`).
2. **Set up Node** — `actions/setup-node@v6` with `node-version: 20` (for the
   test gate and the JSON bump).
3. **Validate inputs** — fail fast:
   - `version` must match `^[0-9]+\.[0-9]+\.[0-9]+$` → else `::error::` + exit 1.
   - tag must not already exist (`git rev-parse "$VERSION"` succeeds → error).
4. **Test gate** — `node --test tests/eventlogic.test.js`. A failing logic suite
   aborts the release before anything is tagged.
5. **Bump version** — set `KPlugin.Version` in `package/metadata.json` via a
   `node -e` script that round-trips JSON with the file's 4-space indent +
   trailing newline (key order is preserved by `JSON.stringify`):
   ```js
   const fs = require('fs'), p = 'package/metadata.json';
   const m = JSON.parse(fs.readFileSync(p, 'utf8'));
   m.KPlugin.Version = process.env.VERSION;
   fs.writeFileSync(p, JSON.stringify(m, null, 4) + '\n');
   ```
6. **Package `.plasmoid`** — built *after* the bump so it embeds the new version.
   A `.plasmoid` is a zip whose root holds `metadata.json` + `contents/`:
   ```bash
   cd package && zip -r "../next-up-calendar-$VERSION.plasmoid" . && cd ..
   ```
7. **Commit & tag** — as the CI bot, push the bump commit and the tag to `main`:
   ```bash
   git config user.name "github-actions[bot]"
   git config user.email "github-actions[bot]@users.noreply.github.com"
   git add package/metadata.json
   git commit -m "chore: bump version to $VERSION"
   git tag "$VERSION"
   git push origin HEAD:main
   git push origin "$VERSION"
   ```
   (`HEAD:main` is robust whether checkout left a detached HEAD or a branch. The
   tag is pushed explicitly — not `--tags` — so only this tag goes up.)
8. **Create GitHub Release** — `softprops/action-gh-release@v3`, referencing the
   already-pushed tag:
   - `tag_name: ${{ inputs.version }}`
   - `name: "${{ inputs.version }} — ${{ inputs.title }}"`
   - `files: next-up-calendar-${{ inputs.version }}.plasmoid`
   - `body:` = the supplied notes, followed by an **Install** snippet:
     download the attached `.plasmoid`, then
     `kpackagetool6 -t Plasma/Applet -i next-up-calendar-<version>.plasmoid`
     (or *Add Widgets → Get New Widgets → Install Widget From Local File…*).
   - env `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}`.

## Component: `README.md` edits

- **Release badge** at the top (below the H1):
  `[![Release](https://img.shields.io/github/v/release/dbtdsilva/plasma-nextup-calendar)](https://github.com/dbtdsilva/plasma-nextup-calendar/releases)`.
  It reads the latest GitHub Release automatically — no workflow step keeps it in
  sync (a simplification over money-nest's `sed`-updated static badge).
- **"Releasing" section** (after Development): document that releases are cut by
  running the **Release** workflow from the Actions tab with version/title/notes,
  and that it bumps `metadata.json`, tags `X.Y.Z`, and publishes the Release with
  the `.plasmoid` attached.

The Features/Limitations prose is left untouched (out of scope for release
tooling).

## Data flow

Maintainer opens Actions → **Release** → enters version/title/notes → Run.
Workflow validates → runs tests → bumps `metadata.json` → zips `.plasmoid` →
commits + tags + pushes to `main` → creates the GitHub Release with the artifact.
The README badge then reflects the new release automatically.

## Error handling

- Bad version string or pre-existing tag → hard fail in step 3 (nothing mutated).
- Failing tests → hard fail in step 4 (before any tag/commit).
- `action-gh-release` fails if the release already exists for the tag.
- Push to `main` assumes no branch protection blocks the Actions bot; if
  protection is later added, the token needs bypass (documented, not handled).

## Testing / verification

No new application logic — `eventlogic.js` and its 37 Node tests are unchanged;
the workflow merely runs them as a gate. Verification of this change:

1. YAML is well-formed; run `actionlint` if available.
2. Run the **bump** `node -e` script locally against a copy and confirm only
   `KPlugin.Version` changes and formatting/key-order is preserved.
3. Run the **zip** command locally and confirm
   `kpackagetool6 -t Plasma/Applet -i next-up-calendar-<v>.plasmoid` accepts the
   produced package (then remove the throwaway install).
4. The full end-to-end (dispatch → tag → Release) is exercised when the
   maintainer cuts the first real release (`0.2.0`).

## Out of scope

- Automatic version derivation / changelog from Conventional Commits
  (semantic-release) — a possible later step.
- staging→production promotion, Expo/EAS/OTA, Docker images, milestone sweep
  (money-nest stages that don't apply here).
- A separate PR/push CI workflow (test-on-PR) — could be added later; this task
  is only the release workflow.
- Publishing to store.kde.org (the produced `.plasmoid` is the artifact you'd
  upload there, but the upload itself stays manual).
