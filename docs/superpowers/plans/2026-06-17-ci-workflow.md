# CI Verification Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CI workflow that verifies the widget on every push to `main` and every PR — a fast `test` job (logic tests + static checks) and a `validate` job (QML lint + plasmoid package validation) — plus a README CI badge.

**Architecture:** One workflow `.github/workflows/ci.yml` with two parallel jobs split by toolchain: `test` (Node + python3, zero installs, seconds) and `validate` (apt-installs the Qt6/KDE stack, runs `qmllint` with a tolerant `.qmllint.ini` and a `kpackagetool6` package-validate into a throwaway root). A `.qmllint.ini` keeps unresolved Plasma imports non-fatal.

**Tech Stack:** GitHub Actions (`actions/checkout@v6`, `actions/setup-node@v6`), Node 20, `python3` (preinstalled on the runner), Qt6 `qmllint`, `kpackagetool6` (plasma-sdk).

**Spec:** `docs/superpowers/specs/2026-06-17-ci-workflow-design.md`

**Conventions (repo memory):** Conventional Commits, linear history, repo-local author identity already configured. Do NOT add any Co-Authored-By / Claude / Anthropic / "Generated with" trailer to commits.

**Verifiability note (read before executing):**
- Task 1 (`test` job) and Task 3 (README) are fully deterministic and were dry-run during planning — they pass locally.
- Task 2's `validate` job has two parts: the **`kpackagetool6` package-validate is locally verifiable** (the tool is installed on this machine and the command succeeds) and the YAML parses; but the **`qmllint` step + the apt package set can only be truly confirmed on the GitHub runner** (`qmllint` is not installed here, and exact apt package names vary by the runner's Ubuntu release). Task 2's in-sandbox acceptance is therefore "YAML parses + kpackagetool6 validate passes locally"; the **`qmllint`/apt acceptance is deferred to the "Runner Confirmation" section** (push the branch, watch CI, tune `.qmllint.ini`/packages, or apply the documented fallback). Do not block Task 2 on running `qmllint` in the sandbox.

**Facts verified during planning (all green locally):** `node --test tests/eventlogic.test.js` → 37/37; `metadata.json` parses as JSON; `config/main.xml` parses as XML; all `package/contents/**/*.{qml,js,xml}` carry an SPDX header; `kpackagetool6 --type Plasma/Applet --install package --packageroot "$(mktemp -d)"` → "Successfully installed …". `qmllint` is NOT installed locally.

---

## File Structure

- `.github/workflows/ci.yml` — **create.** The CI workflow (jobs `test` + `validate`). Tasks 1 (test job + skeleton) and 2 (validate job).
- `.qmllint.ini` — **create.** qmllint severity config making unresolved imports non-fatal. Task 2.
- `README.md` — **modify.** Add a CI status badge. Task 3.

---

## Task 1: CI workflow skeleton + `test` job

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow with the `test` job**

Create `.github/workflows/ci.yml` with exactly this content:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Set up Node.js
        uses: actions/setup-node@v6
        with:
          node-version: 20

      - name: Run logic tests
        run: node --test tests/eventlogic.test.js

      - name: Validate metadata.json is valid JSON
        run: python3 -c "import json; json.load(open('package/metadata.json'))"

      - name: Validate config/main.xml is well-formed
        run: python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml')"

      - name: Check SPDX headers on sources
        run: |
          missing=$(grep -RL "SPDX-License-Identifier" --include='*.qml' --include='*.js' --include='*.xml' package/contents || true)
          if [ -n "$missing" ]; then
            echo "::error::sources missing SPDX-License-Identifier:"
            echo "$missing"
            exit 1
          fi
          echo "SPDX headers present on all sources"
```

- [ ] **Step 2: Verify the YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML OK')"`
Expected: `YAML OK`. (PyYAML loads the `on:` key as boolean `True` — a YAML 1.1 quirk, not an error; GitHub parses it correctly.)

- [ ] **Step 3: Run every `test`-job command locally to confirm they pass**

Run:
```bash
node --test tests/eventlogic.test.js 2>&1 | grep -E "# tests|# pass|# fail"
python3 -c "import json; json.load(open('package/metadata.json')); print('JSON OK')"
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml'); print('XML OK')"
missing=$(grep -RL "SPDX-License-Identifier" --include='*.qml' --include='*.js' --include='*.xml' package/contents || true); [ -z "$missing" ] && echo "SPDX OK" || { echo "MISSING: $missing"; exit 1; }
```
Expected: `# tests 37 / # pass 37 / # fail 0`, then `JSON OK`, `XML OK`, `SPDX OK`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add test job (logic tests + static checks)"
```

---

## Task 2: `validate` job + `.qmllint.ini`

Adds the KDE/Qt verification job. The `kpackagetool6` package-validate and YAML are confirmed locally; the `qmllint` step + apt package set are confirmed on the runner (see "Runner Confirmation").

**Files:**
- Create: `.qmllint.ini`
- Modify: `.github/workflows/ci.yml` (append the `validate` job)

- [ ] **Step 1: Create `.qmllint.ini`**

Create `.qmllint.ini` at the repo root with this content. It downgrades the import / unresolved-type categories so a Plasma import a runner lacks does not fail the lint, while real syntax/structural problems still do:

```ini
# Keep unresolved Plasma/Kirigami imports non-fatal in CI: a vanilla runner
# may not provide every org.kde.plasma.* QML module. Real syntax and
# structural errors still fail the lint. Category IDs come from
# `qmllint --help-warnings`; tune on the runner (see the plan's Runner
# Confirmation section) if a name differs on the installed Qt version.
[Warnings]
import=info
unresolved-type=info
```

- [ ] **Step 2: Append the `validate` job to `.github/workflows/ci.yml`**

Add this job under `jobs:` (after the `test` job, same indentation level as `test:`):

```yaml
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Install Qt6 qmllint, QML modules, and kpackagetool6
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            qt6-declarative-dev-tools \
            qml6-module-qtquick \
            qml6-module-qtquick-controls \
            qml6-module-qtquick-layouts \
            qml6-module-org-kde-kirigami \
            plasma-workspace \
            plasma-sdk

      - name: Lint QML
        run: |
          qmllint package/contents/ui/*.qml package/contents/config/config.qml

      - name: Validate plasmoid package
        run: |
          kpackagetool6 --type Plasma/Applet --install package --packageroot "$(mktemp -d)"
```

Notes for the implementer (do not paste into the file):
- The apt package names are a best-effort set for current Ubuntu; the runner is the source of truth. If a package is missing/renamed or a tool isn't on `PATH` after install, fix the set during Runner Confirmation. `qmllint` may install as `/usr/lib/qt6/bin/qmllint`; if it's not on `PATH`, invoke it by full path or add that dir to `PATH` in the step.
- `qmllint` auto-discovers `.qmllint.ini` from the linted file's directory tree; if it does not on the installed version, pass the categories as CLI flags instead (discover exact flag/category names with `qmllint --help-warnings`).

- [ ] **Step 3: Verify the YAML still parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML OK')"`
Expected: `YAML OK`.

- [ ] **Step 4: Confirm the `validate` job's locally-runnable command passes**

Run (the tool is installed on this machine):
```bash
TMP=$(mktemp -d); kpackagetool6 --type Plasma/Applet --install package --packageroot "$TMP" && echo "PKG VALIDATE OK"; rm -rf "$TMP"
```
Expected: `Successfully installed …/com.github.dbtdsilva.nextupcalendar/` then `PKG VALIDATE OK`.

(Do NOT attempt to run `qmllint` here — it is not installed; its acceptance is the Runner Confirmation step. Do not `apt-get install` on this machine.)

- [ ] **Step 5: Commit**

```bash
git add .qmllint.ini .github/workflows/ci.yml
git commit -m "ci: add validate job (qmllint + package validation)"
```

---

## Task 3: README CI badge

**Files:**
- Modify: `README.md` (add a CI badge beside the existing release badge under the H1)

- [ ] **Step 1: Add the CI badge**

In `README.md`, replace:

```markdown
[![Release](https://img.shields.io/github/v/release/dbtdsilva/plasma-nextup-calendar)](https://github.com/dbtdsilva/plasma-nextup-calendar/releases)
```

with:

```markdown
[![CI](https://github.com/dbtdsilva/plasma-nextup-calendar/actions/workflows/ci.yml/badge.svg)](https://github.com/dbtdsilva/plasma-nextup-calendar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/dbtdsilva/plasma-nextup-calendar)](https://github.com/dbtdsilva/plasma-nextup-calendar/releases)
```

- [ ] **Step 2: Verify the edit landed**

Run: `grep -n "actions/workflows/ci.yml/badge.svg" README.md && echo "BADGE OK"`
Expected: a matching line, then `BADGE OK`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add CI status badge to README"
```

---

## Runner Confirmation (acceptance for the `validate` job)

The `qmllint` step and the apt package set cannot be proven in the sandbox. After the three tasks are committed, confirm them on the GitHub runner — this is the acceptance gate for the `validate` job and must be done before the work is considered fully complete:

- [ ] Push the branch and open a PR (the finishing step does this), then watch CI:
  ```bash
  gh run watch "$(gh run list --workflow=ci.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
  ```
  or inspect with `gh run view --log-failed`.
- [ ] **`test` job** must be green (expected — all its commands pass locally).
- [ ] **`validate` job**:
  - If the apt step fails (missing/renamed package, tool not on `PATH`): fix the package set / invoke `qmllint` by full path; push again.
  - If `qmllint` reports failures: determine whether they are **real** (genuine syntax/structural issues in our QML → fix the QML) or **import-resolution noise** (an `org.kde.plasma.*` module the runner lacks → broaden `.qmllint.ini` categories, discovered via `qmllint --help-warnings`).
  - **Fallback (explicit, per spec):** if `qmllint` cannot be made reliably green without silencing real errors, degrade it to syntax-only (lint with imports fully disabled) or remove the `Lint QML` step (and `.qmllint.ini`), keeping the package-validate. Record which outcome was taken in the PR description.
- [ ] Iterate push→watch until both jobs are green (or the fallback is applied and green).

---

## Self-Review Notes

- **Spec coverage:** triggers push:[main] + pull_request, contents:read ✓ (T1); `test` job — node tests, JSON validity, XML validity, SPDX presence ✓ (T1); `validate` job — apt install of qmllint/QML modules/kpackagetool6, qmllint with `.qmllint.ini`, package-validate into throwaway root ✓ (T2); README CI badge ✓ (T3); qmllint fallback documented ✓ (Runner Confirmation); side-effect-free package validate via `mktemp -d` ✓ (T2). Out-of-scope items (apt caching, full REUSE, formatters, plasmoidviewer smoke) — absent.
- **Placeholder scan:** no "TBD"/"implement later". The apt package set and `.qmllint.ini` categories are concrete best-effort values with an explicit, bounded runner-tuning step + fallback — not open-ended placeholders.
- **Name/path consistency:** workflow file `.github/workflows/ci.yml`; jobs `test` / `validate`; badge URL `…/actions/workflows/ci.yml/badge.svg`; package path `package`; repo slug `dbtdsilva/plasma-nextup-calendar`; commands match the locally-verified ones — consistent across tasks, README, and verification.
