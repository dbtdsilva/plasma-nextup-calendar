# Unified Imminent Threshold + Bold Panel Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the two "minutes before" settings into one imminent threshold that drives both the orange status dot and the notification, and add an optional bold-panel-text toggle.

**Architecture:** `evaluateAlert` (pure, in `eventlogic.js`) reads the shared threshold from `opts.urgentThresholdMinutes` (the value that already drives the dot via `formatPanelText`); the separate `alertMinutesBefore` config is removed. A new `panelBold` config flows as a `bold` property to `CompactRepresentation`, setting the label's `font.bold` (pure styling).

**Tech Stack:** Plasma 6 QML (QtQuick / Kirigami / QtQuick.Controls), pure-JS logic tested with Node's `node:test`.

**Spec:** `docs/superpowers/specs/2026-06-17-unified-threshold-and-bold-design.md`

## Global Constraints

- Pure decision logic stays in `package/contents/js/eventlogic.js` (no QML/Node APIs); QML is styling/wiring only.
- Keep the config key `urgentThresholdMinutes` (do NOT rename) to preserve stored values; threshold range stays `0–60`.
- Conventional Commits; repo-local author identity already configured; do NOT add any Co-Authored-By / Claude / Anthropic / "Generated with" trailer.
- Test command: `node --test tests/eventlogic.test.js` (currently 37 tests; this change renames fields in existing fixtures — the count stays 37).

---

## Task 1: `evaluateAlert` uses the unified threshold

**Files:**
- Modify: `package/contents/js/eventlogic.js` (`evaluateAlert`, line 184)
- Test: `tests/eventlogic.test.js` (the `evaluateAlert` fixtures, lines 255 and 259)

**Interfaces:**
- Produces: `evaluateAlert(selection, now, opts, lastAlertedKey)` now reads the threshold from `opts.urgentThresholdMinutes` (was `opts.alertMinutesBefore`). Return shape unchanged: `{ fire, key }`. `opts.alertEnabled` unchanged.
- Consumes: `eventKey` (existing, unchanged).

- [ ] **Step 1: Update the test fixtures to the new opts field**

In `tests/eventlogic.test.js`, change the two places that name the threshold field (all six `evaluateAlert` tests use these):

Line 255 — replace:
```js
const ALERT_OPTS = { alertEnabled: true, alertMinutesBefore: 5 };
```
with:
```js
const ALERT_OPTS = { alertEnabled: true, urgentThresholdMinutes: 5 };
```

In the "disabled never fires" test, replace:
```js
    assert.deepEqual(L.evaluateAlert(sel, NOW, { alertEnabled: false, alertMinutesBefore: 5 }, ""), { fire: false, key: "" });
```
with:
```js
    assert.deepEqual(L.evaluateAlert(sel, NOW, { alertEnabled: false, urgentThresholdMinutes: 5 }, ""), { fire: false, key: "" });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test tests/eventlogic.test.js`
Expected: FAIL — the "fires once within threshold" and "new event after a previous alert" cases fail: the implementation still reads `o.alertMinutesBefore` (now `undefined`), so `mins <= undefined` is `false` and no alert fires when one is expected.

- [ ] **Step 3: Update `evaluateAlert` to read the unified threshold**

In `package/contents/js/eventlogic.js`, replace line 184:
```js
    if (mins <= o.alertMinutesBefore) {
```
with:
```js
    if (mins <= o.urgentThresholdMinutes) {
```
(Nothing else in `evaluateAlert` changes — the `alertEnabled`/`kind`/`key` guards and the `Math.ceil` minute math are untouched.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "refactor: evaluateAlert uses the unified urgentThresholdMinutes"
```

---

## Task 2: Wire the unified threshold; remove `alertMinutesBefore`

**Files:**
- Modify: `package/contents/ui/main.qml` (`evaluateAlert` opts, lines 61-64)
- Modify: `package/contents/config/main.xml` (reword `urgentThresholdMinutes` label; remove `alertMinutesBefore` entry)
- Modify: `package/contents/ui/configGeneral.qml` (remove the `alertMinutesBefore` alias + SpinBox; reword the threshold and alert labels)

**Interfaces:**
- Consumes: `evaluateAlert` expecting `opts.urgentThresholdMinutes` (from Task 1).
- Produces: no more `alertMinutesBefore` config key or `cfg_alertMinutesBefore` alias anywhere.

- [ ] **Step 1: Feed the unified threshold to `evaluateAlert` in `main.qml`**

In `package/contents/ui/main.qml`, replace:
```qml
        const alert = Logic.evaluateAlert(selection, now, {
            alertEnabled: cfg.alertEnabled,
            alertMinutesBefore: cfg.alertMinutesBefore,
        }, root.lastAlertedKey);
```
with:
```qml
        const alert = Logic.evaluateAlert(selection, now, {
            alertEnabled: cfg.alertEnabled,
            urgentThresholdMinutes: cfg.urgentThresholdMinutes,
        }, root.lastAlertedKey);
```

- [ ] **Step 2: Remove `alertMinutesBefore` and reword the threshold in `main.xml`**

In `package/contents/config/main.xml`, reword the `urgentThresholdMinutes` label — replace:
```xml
            <label>Minutes-before threshold that turns the panel status dot orange</label>
```
with:
```xml
            <label>Minutes before the next event that count as imminent (turns the status dot orange and, if enabled, fires the notification)</label>
```

Then delete the entire `alertMinutesBefore` entry:
```xml
        <entry name="alertMinutesBefore" type="Int">
            <label>Minutes before the next event to notify</label>
            <default>5</default>
        </entry>
```
(Leave the `alertEnabled` entry directly above it in place.)

- [ ] **Step 3: Update the config page in `configGeneral.qml`**

In `package/contents/ui/configGeneral.qml`:

(a) Remove the alias line:
```qml
    property alias cfg_alertMinutesBefore: alertMinutesBefore.value
```

(b) Reword the threshold SpinBox label — replace:
```qml
        Kirigami.FormData.label: i18n("Turn the status dot orange within (minutes):")
```
with:
```qml
        Kirigami.FormData.label: i18n("Mark the next event imminent within (minutes):")
```

(c) Reword the alert CheckBox label — replace:
```qml
    QQC2.CheckBox {
        id: alertEnabled
        Kirigami.FormData.label: i18n("Notify before the next event:")
        text: i18n("Show a desktop notification")
    }
```
with:
```qml
    QQC2.CheckBox {
        id: alertEnabled
        Kirigami.FormData.label: i18n("Notify when imminent:")
        text: i18n("Show a desktop notification")
    }
```

(d) Delete the now-unused minutes SpinBox (the whole block):
```qml
    QQC2.SpinBox {
        id: alertMinutesBefore
        Kirigami.FormData.label: i18n("Minutes before:")
        from: 1
        to: 120
        enabled: alertEnabled.checked
    }
```
After this, the **Alert** section contains only the `alertEnabled` CheckBox.

- [ ] **Step 4: Verify XML parses and the JS suite is green**

Run:
```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml'); print('XML OK')"
node --test tests/eventlogic.test.js 2>&1 | grep -E "# tests|# pass|# fail"
grep -rn "alertMinutesBefore" package/ && echo "LEFTOVER alertMinutesBefore" || echo "no alertMinutesBefore left"
```
Expected: `XML OK`; `# tests 37 / # pass 37 / # fail 0`; `no alertMinutesBefore left`.

- [ ] **Step 5: Commit**

```bash
git add package/contents/ui/main.qml package/contents/config/main.xml package/contents/ui/configGeneral.qml
git commit -m "feat: unify the imminent threshold for the dot and the alert"
```

---

## Task 3: Bold panel text toggle

**Files:**
- Modify: `package/contents/config/main.xml` (add `panelBold` entry)
- Modify: `package/contents/ui/CompactRepresentation.qml` (add `bold` property + `font.bold`)
- Modify: `package/contents/ui/main.qml` (pass `bold` to `CompactRepresentation`)
- Modify: `package/contents/ui/configGeneral.qml` (add `cfg_panelBold` alias + CheckBox)

**Interfaces:**
- Produces: config key `panelBold` (Bool, default false); `CompactRepresentation` requires a `bool bold` property.
- Consumes: nothing from Tasks 1-2 (independent).

- [ ] **Step 1: Add the `panelBold` config entry**

In `package/contents/config/main.xml`, insert this entry immediately after the closing `</entry>` of the `panelHideAllDay` entry (and before the `popupHideAllDay` entry):
```xml
        <entry name="panelBold" type="Bool">
            <label>Show the panel event text in bold</label>
            <default>false</default>
        </entry>
```

- [ ] **Step 2: Add the `bold` property and bind `font.bold` in `CompactRepresentation.qml`**

In `package/contents/ui/CompactRepresentation.qml`, after the `isExpanded` property add a `bold` property — replace:
```qml
    // current popup state, captured at press time for reliable click-to-close
    required property bool isExpanded
```
with:
```qml
    // current popup state, captured at press time for reliable click-to-close
    required property bool isExpanded
    // bold the panel text (from Plasmoid.configuration.panelBold)
    required property bool bold
```

Then set the label's weight — replace:
```qml
            text: compactRoot.panelModel.text
            color: Kirigami.Theme.textColor
        }
```
with:
```qml
            text: compactRoot.panelModel.text
            color: Kirigami.Theme.textColor
            font.bold: compactRoot.bold
        }
```

- [ ] **Step 3: Pass `bold` from `main.qml`**

In `package/contents/ui/main.qml`, replace the compact representation block:
```qml
    compactRepresentation: CompactRepresentation {
        panelModel: root.panelModel
        isExpanded: root.expanded
        onActivated: wasExpanded => root.expanded = !wasExpanded
    }
```
with:
```qml
    compactRepresentation: CompactRepresentation {
        panelModel: root.panelModel
        isExpanded: root.expanded
        bold: Plasmoid.configuration.panelBold
        onActivated: wasExpanded => root.expanded = !wasExpanded
    }
```

- [ ] **Step 4: Add the config-page toggle in `configGeneral.qml`**

(a) After the `cfg_panelHideAllDay` alias, add:
```qml
    property alias cfg_panelBold: panelBold.checked
```

(b) In the **Next up (panel)** section, immediately after the `panelHideAllDay` CheckBox block (and before the "Agenda popup" `Kirigami.Separator`), add:
```qml
    QQC2.CheckBox {
        id: panelBold
        Kirigami.FormData.label: i18n("Bold panel text:")
        text: i18n("Show the event in bold")
    }
```

- [ ] **Step 5: Verify XML parses and the JS suite is green**

Run:
```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml'); print('XML OK')"
node --test tests/eventlogic.test.js 2>&1 | grep -E "# tests|# pass|# fail"
```
Expected: `XML OK`; `# tests 37 / # pass 37 / # fail 0`.

- [ ] **Step 6: Commit**

```bash
git add package/contents/config/main.xml package/contents/ui/CompactRepresentation.qml package/contents/ui/main.qml package/contents/ui/configGeneral.qml
git commit -m "feat: optional bold panel text"
```

---

## Verification (after all tasks)

Automated:
- [ ] `node --test tests/eventlogic.test.js` → 37 pass / 0 fail.
- [ ] `python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml')"` → OK.
- [ ] `grep -rn "alertMinutesBefore" package/` → no matches.
- [ ] On push, CI's `validate` job runs `qmllint` (ubuntu:26.04 container) over `CompactRepresentation.qml`/`configGeneral.qml`. Watch with `gh run watch`.

Visual (maintainer, Plasma session): `./install.sh` then `systemctl --user restart plasma-plasmashell.service`:
- [ ] Config → General: the **Alert** section has only the enable toggle; the panel section has one "Mark the next event imminent within (minutes):" spinbox and a "Bold panel text" checkbox.
- [ ] With alerts on, the dot turning orange and the notification both happen at the same configured minute.
- [ ] Toggling "Bold panel text" bolds/unbolds the panel event text.

---

## Self-Review Notes

- **Spec coverage:** evaluateAlert reads `urgentThresholdMinutes` ✓ (T1); `alertMinutesBefore` removed from config/UI/main.qml ✓ (T2); threshold + alert labels reworded ✓ (T2); evaluateAlert tests switch the opts field ✓ (T1); `panelBold` config + `bold` property + `font.bold` + config toggle ✓ (T3); key `urgentThresholdMinutes` kept, range 0–60 ✓; bold is pure styling, no logic/test ✓.
- **Placeholder scan:** none — every step has concrete code/commands.
- **Type/name consistency:** opts field `urgentThresholdMinutes` matches across `evaluateAlert` (T1), its tests (T1), and `main.qml`'s call (T2); config key `panelBold` matches the `cfg_panelBold` alias and the `bold` property it feeds (T3); `CompactRepresentation`'s new `required property bool bold` is supplied by `main.qml` (T3).
