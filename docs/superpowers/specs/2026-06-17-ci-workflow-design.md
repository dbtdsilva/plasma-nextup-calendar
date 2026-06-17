# CI Verification Workflow — Design

**Date:** 2026-06-17
**Status:** Approved (validate job revised — see Revision below)
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

> **Revision (2026-06-17):** The original `validate` job apt-installed the Qt6/KF6
> stack directly on `ubuntu-latest`. That fails: GitHub's `ubuntu-latest` runner
> is **24.04 (noble)**, which ships **Plasma 5 / KF5** — no `kpackagetool6`, no Qt6
> Kirigami QML module. Verified against the noble archive. The job now runs inside
> a **`container: ubuntu:26.04`**, which carries the full Plasma 6 / Qt6 / KF6 stack
> (matching the versions the widget targets), with the toolchain apt-installed
> there (`qt6-declarative-dev-tools`, `qml6-module-qtquick{,-controls,-layouts}`,
> `qml6-module-org-kde-kirigami`, `plasma-workspace`, `kpackagetool6`). Verified
> locally in that container against the real sources: `qmllint` exits 0 (all
> imports resolve; only non-fatal unqualified-access warnings) and `kpackagetool6`
> validates the package. The `.qmllint.ini` import-downgrade is **dropped** — every
> import resolves in this image, so it is unnecessary. The `test` job is unchanged.

## Purpose

Add a continuous-integration workflow that verifies the widget on every push to
`main` and every pull request — the plasmoid analogue of money-nest's
`ci.yml` (which runs `lint test build typecheck` for its TS monorepo). Scope
chosen: **Full** — logic tests + cheap static checks + QML lint + plasmoid
package validation.

## Triggers & permissions

```yaml
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
```

Mirrors money-nest. The release workflow (`release.yml`) pushes a bump commit to
`main`, which re-triggers this CI on `main` — harmless (it just reconfirms
green) and there is no workflow→workflow loop (`GITHUB_TOKEN` pushes don't
trigger workflows, and even a normal push only runs CI, which pushes nothing).

## Job layout

Two jobs, split by toolchain so the fast checks give quick feedback and run in
parallel with the slow KDE/Qt install:

### Job `test` — fast, no extra installs (seconds)

Runner: `ubuntu-latest`.

1. `actions/checkout@v6`.
2. `actions/setup-node@v6` with `node-version: 20`.
3. **Logic tests:** `node --test tests/eventlogic.test.js` (37 tests, pure JS).
4. **JSON validity:** `python3 -c "import json; json.load(open('package/metadata.json'))"`.
5. **XML well-formedness:** `python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml')"`.
6. **SPDX header presence:** every source under `package/contents/` matching
   `*.qml`, `*.js`, or `*.xml` must contain `SPDX-License-Identifier`; fail and
   list any that don't. `package/metadata.json` is excluded (JSON has no
   comment syntax to carry an SPDX tag).

`python3` is preinstalled on `ubuntu-latest`; this job needs no `apt`.

### Job `validate` — KDE/Qt toolchain (a few minutes, install-dominated)

Runner: `ubuntu-latest`.

1. `actions/checkout@v6`.
2. **Install toolchain** via `sudo apt-get update && sudo apt-get install -y …`:
   - `qmllint` (Qt6 declarative dev tools),
   - the QML modules the widget imports — QtQuick / QtQuick.Controls /
     QtQuick.Layouts, Kirigami, and the Plasma QML plugins including
     `org.kde.plasma.workspace.calendar`, `…plasmoid`, `…plasma5support`,
     `…core/components/extras`,
   - `kpackagetool6` (from `plasma-sdk`).

   **The exact apt package names are not pinned in this spec** — they vary by the
   runner's Ubuntu release. The implementation step installs them, confirms each
   tool/module is present, and tunes the set until the two checks below pass on
   the current (known-good) sources.
3. **QML lint:** run `qmllint` over `package/contents/ui/*.qml` and
   `package/contents/config/config.qml`. A committed **`.qmllint.ini`** downgrades
   the unresolved-import category to non-fatal, so the lint fails on real
   syntax/structural errors but not on an `org.kde.plasma.*` import a runner
   happens to lack. **Acceptance gate: green on the current repo.**
4. **Package validation:**
   `kpackagetool6 --type Plasma/Applet --install package --packageroot "$(mktemp -d)"`
   — installs into a throwaway root, validating package structure +
   `metadata.json` without touching the real user/system package dirs. Fails on a
   malformed package.

## README

Add a CI status badge beside the existing release badge under the H1:
`[![CI](https://github.com/dbtdsilva/plasma-nextup-calendar/actions/workflows/ci.yml/badge.svg)](https://github.com/dbtdsilva/plasma-nextup-calendar/actions/workflows/ci.yml)`.

## Error handling / known risks

- **QML-lint reliability is the one genuine unknown.** Fully resolving every
  Plasma import on a vanilla runner is brittle. Mitigation: install as much of
  the stack as available and downgrade unresolved-import to non-fatal via
  `.qmllint.ini`. **Fallback (explicit):** if `qmllint` cannot be made reliably
  green without silencing real errors, the implementation degrades it to
  syntax-only or drops the QML-lint step — rather than ship a noisy or
  always-green check. This decision is made during implementation, with the
  outcome recorded.
- The `validate` job runs `apt-get` on every run (no caching — YAGNI; can be
  added later if the few-minutes cost becomes annoying).
- `kpackagetool6 --packageroot "$(mktemp -d)"` keeps validation side-effect-free
  (does not collide with the maintainer's already-installed widget).

## Testing / verification

No application code changes — `eventlogic.js` and its 37 tests are untouched;
this workflow merely runs them. Verifying the change itself:

1. `ci.yml` parses as YAML (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`).
2. Every `test`-job command run locally is green (they already are: tests pass,
   `metadata.json`/`main.xml` parse, all `package/contents` sources carry SPDX).
3. The `validate` job can only be fully proven on the runner — the
   implementation either runs the tools locally after installing them, or
   confirms via a throwaway branch push that the job goes green. The plan calls
   this out as the acceptance step for that job.

## Out of scope

- apt/dependency caching, build-matrix across Qt/Plasma versions.
- Full REUSE compliance tooling (`reuse lint` + `LICENSES/` tree) — only an
  SPDX-header-presence grep is done here.
- Auto-formatting / style enforcement beyond syntax (no prettier/eslint; the JS
  is plain and the repo has no formatter configured).
- Running the widget headless in a real Plasma session (no `plasmoidviewer`
  smoke test) — package validation is the structural substitute.
