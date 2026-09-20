# Feature: widgets on the free side of the notch

**Goal**: use the ~550 px left of the notch for a paneru workspace row, and stop
polling paneru once per second by consuming its event stream.

**Why now**: the bar was rebalanced so the pill and the right cluster fit their
band; that left the space between the left cluster and the notch unused. Measured
with a column profile of a full-bar screenshot: the left cluster ends at x≈220
and the notch starts at x=770, so ~550 px are free. At 12pt the bar's font
advances 7 px per character, so that region fits ~78 characters.

**Context**: `current_space` renders only the active space as one pill, polled at
`update_freq=1`. paneru exposes the full list (`query virtual-workspaces --json`,
entries carry `active`, `native_workspace_id`, `number` and their windows), a
coalesced event stream (`subscribe --json`), and
`paneru send-cmd window virtualnum N` to switch spaces.

**Sources**: https://github.com/karinushka/paneru — `QUERY_AND_SUBSCRIBE_FORMAT.md`
and `CONFIGURATION.md`. Verified locally against paneru 0.5.1: the payloads above,
the command vocabulary (an invalid argument yields "unhandled virtual workspace",
an invalid name yields "invalid command"), and that `paneru.exec` exists in the
Lua API (undocumented).

## Tasks

- [x] 1. Replace `current_space` with a workspace row for the active display.
  - Acceptance: only the active `native_workspace_id`'s spaces render; the active
    one carries the accent surface with dark ink, the others the neutral surface
    with light ink; items past the count are `drawing=off`; clicking pill N runs
    `paneru send-cmd window virtualnum N`; when no space is active every pill is
    hidden rather than showing a stale number.
  - Why a fixed maximum of 9: sketchybar lays left items out in creation order, so
    adding a pill at runtime would place it after `front_app`. The config
    pre-creates `space.1`..`space.9` and the plugin only toggles them.
  - Done: `plugins/workspace_row.sh` replaces `plugins/current_space.sh`, and the
    config builds the row before `front_app`. The list's own `active` flag is the
    filter, which saves the second query per tick and was checked against
    `paneru query active --json` (both reported native 5 / workspace 1).
- [ ] 2. Migrate the paneru-fed items from `update_freq` polling to the event
  stream (`virtual_workspace_changed`, `windows_changed`, `window_focused`,
  `window_title_changed`, `display_changed`).
  - Why it is separate: a subscriber needs a supervisor (launchd agent) plus an
    install-manifest row, and this repo manages no launch agents today. Shipping
    half of it would leave a subscriber that dies with the bar or duplicates on
    every reload.
- [ ] 3. Offered and not chosen: focused-window title, Bluetooth battery,
  docker/mise. Revisit only if asked.

## Evidence

- Row behaviour: `test/sketchybar.bats` (stubbed `paneru`) — 23/23 green, five of
  them new: the config contract, the display filter, the accent split, the click
  path, and the two degenerate payloads (unreachable daemon, no active space).
- Row live: after `brew services restart sketchybar` the item list carries
  `space.1`..`space.9` and no `current_space`; the pills of the active native
  workspace render (`space.1` accented with `0xffb7bdf8`/`0xff24273a`, the rest
  neutral with `0x66494d64`/`0xffcad3f5`) and `space.5`..`space.9` are
  `drawing=off`. The error log stayed byte-identical across polls.
- Click path is verified by test only: firing it live would move the user's
  windows, so the daemon-side vocabulary was proven with invalid arguments
  instead (`unhandled virtual workspace 'x'` vs `invalid command`).
- Event names for task 2: `QUERY_AND_SUBSCRIBE_FORMAT.md` § Event Types.
