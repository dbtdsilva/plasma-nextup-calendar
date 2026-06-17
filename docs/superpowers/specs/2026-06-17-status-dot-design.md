# Panel Meeting-Status Dot — Design

**Date:** 2026-06-17
**Status:** Approved
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

Replace the panel's red-text "urgent" styling with a colored status dot before
the event name — at-a-glance meeting state, reusing the treatment from the
`org.kde.plasma.claudeusage` widget (a drawn `Rectangle` dot recolored via the
theme's semantic colors).

## Behavior

A small dot is shown **before** the panel text, **always present**, colored by
the next-up selection's state. The event name itself is rendered in the normal
text color (the previous `urgent → negativeTextColor` red styling is removed).

| State | Dot color (Kirigami.Theme) |
|---|---|
| On a meeting — selection kind `ongoing` | `negativeTextColor` (red) |
| Meeting close — kind `upcoming` and minutes-to-start ≤ `urgentThresholdMinutes` | `neutralTextColor` (orange) |
| All clear — far `upcoming`, `allday`, or `none` | `positiveTextColor` (green) |

These are the same theme colors the claudeusage widget uses
(`positive`/`neutral`/`negativeTextColor`), so the dot adapts to light/dark and
matches Breeze, and it mirrors the colored dot the agenda popup already renders.

The `urgentThresholdMinutes` config keeps its meaning ("how close counts as
close") but now drives the **orange dot** instead of red text.

## Pure logic (`package/contents/js/eventlogic.js`, Node-tested)

`formatPanelText(selection, now, opts, fmtTime)` currently returns
`{ text, urgent }`. Change the return shape to `{ text, status }` where
`status` is one of `"ongoing" | "soon" | "clear"`:

- `selection.kind === "none"` → `{ text: placeholder, status: "clear" }`
- `selection.kind === "ongoing"` → `status: "ongoing"`
- `selection.kind === "allday"` → `status: "clear"`
- `selection.kind === "upcoming"`:
  - minutes-to-start (`Math.ceil((start - now)/60000)`) ≤ `urgentThresholdMinutes`
    → `status: "soon"`
  - otherwise (later today / tomorrow / >threshold) → `status: "clear"`

The `urgent` field is removed. The text strings are unchanged. The
`urgentThresholdMinutes` default (5) and `Math.ceil` minute math are unchanged —
only the field name/semantics change (the same condition that set
`urgent: true` now yields `status: "soon"`).

## QML

`package/contents/ui/CompactRepresentation.qml`:
- The single `Label` becomes a `RowLayout` of `[ dot ][ label ]`.
- **Dot:** `Rectangle { radius: width/2; color: statusColor }`, sized like the
  popup's dot (`Kirigami.Units.smallSpacing * 2`), vertically centered.
- **statusColor** maps `panelModel.status`: `"ongoing"` → `negativeTextColor`,
  `"soon"` → `neutralTextColor`, else → `positiveTextColor`.
- **Label** text = `panelModel.text`, color = `Kirigami.Theme.textColor` always
  (the `urgent` conditional is removed). Keeps `elide: Text.ElideRight`.
- Horizontal and vertical panel sizing is preserved: the row's width is the dot
  + spacing + label width (the label still elides under a thin vertical panel).

`package/contents/ui/main.qml`:
- `panelModel` carries `{ text, status }` (default e.g. `{ text: "…", status: "clear" }`).
- `refresh()` builds `panelModel` from `formatPanelText`'s new return — pass
  `status` through. The `evaluateAlert` path is unchanged.

## Config wording

The threshold no longer "highlights text," so reword it (value/behavior of the
entry is unchanged):
- `package/contents/config/main.xml` — `urgentThresholdMinutes` `<label>`:
  "Minutes-before threshold that turns the panel status dot orange".
- `package/contents/ui/configGeneral.qml` — the SpinBox `FormData.label`:
  "Turn the status dot orange within (minutes):".

## Scope

Panel (`CompactRepresentation`) only. The agenda popup already shows per-event
color dots and is unchanged. No new config entries; no icon asset is added (the
dot is drawn in QML, like the claudeusage widget and our popup).

## Testing

Update `tests/eventlogic.test.js` `formatPanelText` cases to assert `status`
instead of `urgent`:

- ongoing → `status: "ongoing"` (and text still `"… · ends HH:MM"`).
- upcoming within threshold → `status: "soon"`; at exactly the threshold →
  `"soon"`; one minute beyond → `"clear"`.
- upcoming later today / tomorrow → `"clear"`.
- all-day (today and tomorrow variants) → `"clear"`.
- none/placeholder → `status: "clear"`.

No QML is unit-tested; the dot rendering is verified visually via the installed
widget.

## Out of scope

- Changing the popup's dots or adding a dot elsewhere.
- A configurable dot on/off toggle or custom colors (YAGNI — theme colors only).
- Reusing the claudeusage SVG asset (a fixed-green image can't recolor; a
  theme-colored drawn dot is the correct reuse of its approach).
