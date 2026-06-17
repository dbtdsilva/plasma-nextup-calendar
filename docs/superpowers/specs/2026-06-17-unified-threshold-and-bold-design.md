# Unified Imminent Threshold + Bold Panel Text — Design

**Date:** 2026-06-17
**Status:** Approved
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

Two small refinements to the panel:

1. **Unify the "imminent" threshold** — one setting drives both the orange status
   dot and the pre-event notification, instead of two near-identical "minutes
   before" knobs.
2. **Bold panel text** — an optional global toggle to render the panel event text
   in bold.

## Feature 1: Unified imminent threshold

Today there are two settings that both answer "how soon counts as imminent?":
`urgentThresholdMinutes` (orange dot) and `alertMinutesBefore` (notification),
both defaulting to 5. Collapse them into one.

- **Keep `urgentThresholdMinutes`** as the single threshold (default `5`). The
  config *key* is intentionally kept (not renamed) so any stored value is
  preserved; only its meaning broadens and its labels change.
- **Remove `alertMinutesBefore`** — the config entry, its config-page SpinBox,
  and its `cfg_alertMinutesBefore` alias.
- **`evaluateAlert`** (pure, in `eventlogic.js`) reads the threshold from
  `opts.urgentThresholdMinutes` instead of `opts.alertMinutesBefore`. No other
  logic changes: it still fires once when `alertEnabled` and the upcoming event's
  minutes-to-start ≤ the threshold and the key differs from `lastAlertedKey`.
- **`main.qml`** `refresh()` passes
  `{ alertEnabled: cfg.alertEnabled, urgentThresholdMinutes: cfg.urgentThresholdMinutes }`
  to `evaluateAlert`. The same `cfg.urgentThresholdMinutes` already feeds
  `formatPanelText` (the dot), so the dot turning orange and the notification
  firing now coincide at the same minute.
- The `alertEnabled` on/off toggle is unchanged — it gates whether the
  notification fires; the dot is unaffected by it.

### Config wording (`config/main.xml`, `configGeneral.qml`)

- `urgentThresholdMinutes` `<label>`: "Minutes before the next event that count as
  imminent (turns the status dot orange and, if enabled, fires the notification)".
- The threshold SpinBox stays in the **Next up (panel)** section; its
  `FormData.label` → "Mark the next event imminent within (minutes):". Range stays
  `from: 0, to: 60` (`0` ⇒ never imminent, since an upcoming event is always ≥ 1
  minute away). The old alert's `1–120` range is dropped.
- The **Alert** section keeps only the `alertEnabled` CheckBox; reword its
  `FormData.label` → "Notify when imminent:" and keep the inline text
  ("Show a desktop notification").

### evaluateAlert tests

`tests/eventlogic.test.js`: the shared `ALERT_OPTS` and the per-test opts switch
the field name `alertMinutesBefore` → `urgentThresholdMinutes` (same value `5`,
same fire/no-fire assertions). No behavioral change to the six cases.

## Feature 2: Bold panel text

- New config entry **`panelBold`** (Bool, default `false`) in `config/main.xml`.
- `CompactRepresentation.qml` gains `required property bool bold`; the
  `PlasmaComponents.Label` sets `font.bold: compactRoot.bold`. Nothing else about
  the label changes (still `Kirigami.Theme.textColor`, elided, centered).
- `main.qml` passes `bold: Plasmoid.configuration.panelBold` to the
  `CompactRepresentation` (alongside `panelModel` / `isExpanded`).
- **Config UI:** a `QQC2.CheckBox` (`cfg_panelBold`) in the **Next up (panel)**
  section — `FormData.label` "Bold panel text:", inline text "Show the event in
  bold".
- This is pure styling — no `eventlogic.js` change and no new Node test.

## Data flow

`refresh()` → `selectPanelEvent` → `formatPanelText` (status from
`urgentThresholdMinutes`) for the dot/text, and `evaluateAlert` (now also keyed on
`urgentThresholdMinutes`) for the notification. The panel label's weight comes
straight from `panelBold` via the `bold` property — independent of the model.

## Error handling

- Threshold `0`: no upcoming event is ever ≤ 0 minutes away (upcoming requires
  `start > now`), so the dot never goes orange and no alert fires — an effective
  "off", consistent across both consumers.
- Removing `alertMinutesBefore`: KConfigXT simply ignores any previously stored
  value for the dropped key; nothing errors. The alert now uses the (preserved)
  `urgentThresholdMinutes` value.

## Testing

- `evaluateAlert` cases pass with the renamed opts field (37 tests stay green;
  this is a field-name change in the test fixtures, not a count change).
- Bold and the config rewordings are QML/config-only — verified by `node --test`
  staying green, `main.xml` parsing as XML, CI's `qmllint` (ubuntu:26.04 container)
  over the changed QML, and a visual check (install + restart): toggling "Bold
  panel text" bolds the panel text; the single threshold turns the dot orange and
  fires the notification at the same minute.

## Out of scope

- Renaming the `urgentThresholdMinutes` config key (kept to preserve stored
  values).
- Separate dot-vs-alert timings (the whole point is to unify them).
- Bolding the dot, the popup, or making bold state-dependent (it's a plain global
  toggle).
- Per-state fonts/sizes or other panel typography options (YAGNI).
