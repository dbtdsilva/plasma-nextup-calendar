# Manual Release Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manually-triggered GitHub Actions workflow that bumps the widget version, tags it, and publishes a GitHub Release with an installable `.plasmoid` artifact, plus the README badge and "Releasing" docs.

**Architecture:** One `workflow_dispatch` workflow (`.github/workflows/release.yml`) modeled on money-nest's manual release: human supplies version/title/notes → validate → test gate → bump `package/metadata.json` → zip `.plasmoid` → commit + bare `X.Y.Z` tag + push to `main` → `softprops/action-gh-release@v3` with the artifact. README gets a dynamic release badge and a "Releasing" section.

**Tech Stack:** GitHub Actions (`actions/checkout@v6`, `actions/setup-node@v6`, `softprops/action-gh-release@v3`), Node 20 (already used for the test suite), `zip`, `shields.io`.

**Spec:** `docs/superpowers/specs/2026-06-17-release-workflow-design.md`

**Conventions (repo memory):** Conventional Commits, linear history, repo-local author identity already configured. Do NOT add any Co-Authored-By / Claude / Anthropic / "Generated with" trailer to commits.

**Note on "tests":** The deliverables are a workflow YAML and README prose — there is no unit-testable code. "Verification" here means: YAML parses, the embedded bump script and zip command are proven locally (they were dry-run during planning and work), and the real end-to-end is the maintainer dispatching the workflow once. `actionlint` is NOT installed on this machine — treat it as optional.

**Environment facts already verified during planning:**
- The bump `node -e` script changes only `KPlugin.Version` and preserves the 4-space indent + trailing newline + key order.
- `cd package && zip -r ../X.plasmoid .` produces a zip with `metadata.json` at the root and `contents/` — a valid `.plasmoid`.
- Available: `zip`, `unzip`, `python3`, `kpackagetool6`, Node 20. Not available: `actionlint`.

---

## File Structure

- `.github/workflows/release.yml` — **create.** The entire release workflow (first workflow in the repo). One self-contained responsibility: cut a release. (Task 1)
- `README.md` — **modify.** Add the release badge (top) and a "Releasing" section (after Development). (Task 2)

Two independent tasks. Task 1 is the workflow; Task 2 is docs. They can be done in either order but are listed workflow-first so the README text describes the committed workflow.

---

## Task 1: Create the release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/release.yml` with exactly this content:

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Version to release (e.g. 0.2.0)"
        required: true
        type: string
      title:
        description: "Release title (e.g. Filters & alerts)"
        required: true
        type: string
      notes:
        description: "Release notes (markdown)"
        required: true
        type: string

permissions:
  contents: write

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  release:
    runs-on: ubuntu-latest
    env:
      VERSION: ${{ inputs.version }}
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Set up Node.js
        uses: actions/setup-node@v6
        with:
          node-version: 20

      - name: Validate inputs
        run: |
          if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "::error::version must be X.Y.Z (got '$VERSION')"
            exit 1
          fi
          if git rev-parse "$VERSION" >/dev/null 2>&1; then
            echo "::error::tag '$VERSION' already exists"
            exit 1
          fi

      - name: Run logic tests
        run: node --test tests/eventlogic.test.js

      - name: Bump metadata.json version
        run: |
          node -e "
            const fs = require('fs'), p = 'package/metadata.json';
            const m = JSON.parse(fs.readFileSync(p, 'utf8'));
            m.KPlugin.Version = process.env.VERSION;
            fs.writeFileSync(p, JSON.stringify(m, null, 4) + '\n');
          "
          echo "Set KPlugin.Version to $VERSION"

      - name: Package .plasmoid
        run: |
          cd package && zip -r "../next-up-calendar-$VERSION.plasmoid" . && cd ..
          ls -l "next-up-calendar-$VERSION.plasmoid"

      - name: Commit and tag
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add package/metadata.json
          git commit -m "chore: bump version to $VERSION"
          git tag "$VERSION"
          git push origin HEAD:main
          git push origin "$VERSION"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v3
        with:
          tag_name: ${{ inputs.version }}
          name: "${{ inputs.version }} — ${{ inputs.title }}"
          files: next-up-calendar-${{ inputs.version }}.plasmoid
          body: |
            ${{ inputs.notes }}

            ## Install

            Download `next-up-calendar-${{ inputs.version }}.plasmoid` below, then:

            ```
            kpackagetool6 -t Plasma/Applet -i next-up-calendar-${{ inputs.version }}.plasmoid
            ```

            Or use *Add Widgets → Get New Widgets → Install Widget From Local File…*.
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Key correctness points (do not "fix" these):
- `VERSION` is a job-level `env` fed from `inputs.version`; shell steps read `$VERSION` rather than interpolating `${{ }}` into the script body (injection-safe). `title`/`notes` are only ever passed through the action's `with:`, never into a shell.
- `notes` inside the `body: |` block scalar is a literal token at parse time; GitHub substitutes it (multi-line and all) at run time — this is the same pattern money-nest uses.
- The tag is pushed before the release step; `action-gh-release` then reuses the existing tag. `git push origin HEAD:main` works whether checkout left a detached HEAD or a branch.

- [ ] **Step 2: Verify the YAML parses**

Run:
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
```
Expected: `YAML OK`. (Note: PyYAML loads the `on:` key as boolean `True` — a YAML 1.1 quirk, not an error. GitHub parses it correctly. We only care that it parses without raising.)

- [ ] **Step 3: Lint with actionlint if present (optional)**

Run:
```bash
command -v actionlint >/dev/null && actionlint .github/workflows/release.yml && echo "actionlint OK" || echo "actionlint not installed; skipped"
```
Expected: either `actionlint OK` or `actionlint not installed; skipped`. Do not install actionlint just for this.

- [ ] **Step 4: Prove the embedded bump script works (local dry-run, no real file touched)**

Run:
```bash
cp package/metadata.json /tmp/meta-test.json
VERSION=9.9.9 node -e "const fs=require('fs'),p='/tmp/meta-test.json';const m=JSON.parse(fs.readFileSync(p,'utf8'));m.KPlugin.Version=process.env.VERSION;fs.writeFileSync(p,JSON.stringify(m,null,4)+'\n');"
diff package/metadata.json /tmp/meta-test.json
rm -f /tmp/meta-test.json
```
Expected: the only diff is the `"Version"` line (`0.1.0` → `9.9.9`) — confirming indent, key order, and trailing newline are preserved. (Exit status 1 from `diff` is expected because the files differ by that one line.)

- [ ] **Step 5: Prove the `.plasmoid` packaging produces a valid layout (local dry-run)**

Run:
```bash
( cd package && zip -r /tmp/nuc-test.plasmoid . >/dev/null )
unzip -l /tmp/nuc-test.plasmoid | grep -E " metadata.json$" && echo "ROOT METADATA OK"
rm -f /tmp/nuc-test.plasmoid
```
Expected: a `metadata.json` entry at the archive root, then `ROOT METADATA OK`. (A `.plasmoid` must have `metadata.json` at the root; do NOT `kpackagetool6 -i` it here — that would collide with the already-installed widget.)

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add manual release workflow"
```

---

## Task 2: README release badge and "Releasing" section

**Files:**
- Modify: `README.md` (add badge after the H1 on line 1; add a "Releasing" section after the Development section)

- [ ] **Step 1: Add the release badge under the title**

In `README.md`, replace:

```markdown
# Next Up Calendar — Plasma Widget

Shows your next calendar event as text in the Plasma panel — the Plasma
```

with:

```markdown
# Next Up Calendar — Plasma Widget

[![Release](https://img.shields.io/github/v/release/dbtdsilva/plasma-nextup-calendar)](https://github.com/dbtdsilva/plasma-nextup-calendar/releases)

Shows your next calendar event as text in the Plasma panel — the Plasma
```

(The badge auto-reflects the latest GitHub Release; until the first release it renders as "no releases", which is expected.)

- [ ] **Step 2: Add the "Releasing" section after Development**

In `README.md`, replace:

```markdown
## Development

Logic is pure JavaScript with tests: `node --test`
Preview: `plasmoidviewer --applet ./package`

## Limitations
```

with:

```markdown
## Development

Logic is pure JavaScript with tests: `node --test`
Preview: `plasmoidviewer --applet ./package`

## Releasing

Releases are cut manually from the **Actions** tab:

1. Open **Actions → Release → Run workflow**.
2. Enter the **version** (`X.Y.Z`), a **title**, and **notes** (markdown).
3. Run it. The workflow runs the tests, bumps `KPlugin.Version` in
   `package/metadata.json`, tags `X.Y.Z`, pushes to `main`, and publishes a
   GitHub Release with `next-up-calendar-X.Y.Z.plasmoid` attached.

Install a released build by downloading the `.plasmoid` from the release page,
then `kpackagetool6 -t Plasma/Applet -i next-up-calendar-X.Y.Z.plasmoid` (or
*Add Widgets → Get New Widgets → Install Widget From Local File…*).

## Limitations
```

- [ ] **Step 3: Verify the edits landed**

Run:
```bash
grep -n "img.shields.io/github/v/release" README.md && grep -n "^## Releasing" README.md && echo "README OK"
```
Expected: both `grep`s print a matching line, then `README OK`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add release badge and Releasing section to README"
```

---

## Verification (after all tasks)

- [ ] `.github/workflows/release.yml` parses (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`).
- [ ] Bump-script dry-run changes only the `Version` line (Task 1 Step 4).
- [ ] `.plasmoid` dry-run shows root `metadata.json` (Task 1 Step 5).
- [ ] README shows the badge and the Releasing section (Task 2 Step 3).
- [ ] **End-to-end (maintainer-run, not automatable here):** push the branch, merge to `main`, then from the Actions tab run **Release** with version `0.2.0`, a title, and notes. Confirm: a `0.2.0` tag and a `chore: bump version to 0.2.0` commit on `main`, `metadata.json` now `0.2.0`, a GitHub Release `0.2.0 — <title>` with `next-up-calendar-0.2.0.plasmoid` attached, and the README badge showing `0.2.0`.

---

## Self-Review Notes

- **Spec coverage:** workflow trigger/inputs ✓ (T1); validate + no-clobber ✓ (T1); test gate ✓ (T1); metadata bump ✓ (T1); `.plasmoid` packaging + attach ✓ (T1); bot commit + bare tag + push ✓ (T1); `action-gh-release@v3` with body/install snippet ✓ (T1); README dynamic badge ✓ (T2); README Releasing section ✓ (T2). Dropped money-nest stages (EAS/Docker/promotion/milestone) — intentionally absent. Injection-safe input handling ✓ (T1 Step 1 notes).
- **Placeholder scan:** none — every step has concrete content/commands.
- **Name/value consistency:** artifact name `next-up-calendar-<version>.plasmoid`, tag `<version>` (bare), version key `KPlugin.Version`, repo `dbtdsilva/plasma-nextup-calendar`, action `softprops/action-gh-release@v3`, `actions/checkout@v6`, `actions/setup-node@v6` (node 20) — consistent across the workflow, README, and verification steps.
