# Next Up Calendar — Plasma Widget

[![CI](https://github.com/dbtdsilva/plasma-nextup-calendar/actions/workflows/ci.yml/badge.svg)](https://github.com/dbtdsilva/plasma-nextup-calendar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/dbtdsilva/plasma-nextup-calendar)](https://github.com/dbtdsilva/plasma-nextup-calendar/releases)

Shows your next calendar event as text in the Plasma panel — the Plasma
equivalent of GNOME's [Next Up](https://extensions.gnome.org/extension/5278/next-up/)
extension. Click it for a multi-day agenda popup; click a meeting to join
its Teams/Meet/Zoom call directly.

Events come from **Akonadi**, so anything synced by
[Merkuro](https://apps.kde.org/merkuro.calendar/) or KOrganizer works —
including Office365, Google and CalDAV accounts.

## Features

- Next event in the panel: `Standup · in 12 min`, `Standup · 14:30`,
  `Standup · tomorrow 09:00`, with an urgent color when it's about to start
- Ongoing events: `Standup · ends 15:30`
- All-day events when nothing timed is pending
- Agenda popup grouped by day (Today / Tomorrow / weekday)
- Click-to-join: detects Teams, Google Meet and Zoom links in the event
- Configurable lookahead, title length, urgency threshold, placeholder text
  and popup length

## Requirements

- Plasma 6
- `kdepim-addons` (provides the PIM Events calendar plugin)
- Akonadi with your calendars set up (easiest via Merkuro)

## Setup: enable your calendars

This widget reads the calendars enabled in the **PIM Events** plugin. If the
popup says it found no events, enable them once:

1. Right-click the stock Digital Clock → Configure → Calendar
2. Tick **PIM Events Plugin**, then choose your calendars under its settings

(Equivalently, set `calendars=` under `[PIMEventsPlugin]` in
`~/.config/plasmashellrc` to your Akonadi collection IDs.)

## Install

    ./install.sh

Then add **Next Up Calendar** to your panel via *Add Widgets*.

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

- Events are matched by title + start time (the calendar plugin exposes no
  unique id), so two distinct events with the same title and start collapse
  into one in the agenda.
- Meeting-link detection reads the event description only; if your provider
  puts the link solely in the location field, the row falls back to opening
  Merkuro.

## License

GPL-2.0-or-later
