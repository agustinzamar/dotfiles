# Dot TUI Specification

## Purpose

Define the terminal selection UI contract for the `dot` installer: two-pane browsing,
keyboard-driven selection, search, review flow, and viewport behavior. The ported
implementation MUST reproduce this interaction contract 1:1; internal rendering
technology is out of scope.

## Requirements

### Requirement: Two-Pane Selection Layout

The main screen MUST show a category sidebar (left) and a component list (right).
Categories SHALL appear in manifest first-seen order. The right pane lists components
grouped under dim `[category]` headers, with a cursor indicator on exactly one visible
entry. Each component row MUST display a state mark: green `✓` for applied components,
yellow `x` for selected-not-applied, blank otherwise. A status line SHOULD report
installed and selected counts.

#### Scenario: Initial screen state

- GIVEN the TUI starts with an empty applied set
- WHEN the first frame renders
- THEN the sidebar shows all categories in manifest order with the first active
- AND every default/required component shows mark `x`, others blank
- AND no component shows `✓`

#### Scenario: Applied components marked with check

- GIVEN the applied set contains component A's id
- WHEN the list renders
- THEN A's row shows a green `✓` regardless of its selection state

### Requirement: Pane Switching And Navigation

`tab` (and `left`/`right`) MUST toggle focus between sidebar and component pane.
In the sidebar, `up`/`down` move the category cursor within bounds; in the component
pane, `up`/`down` move the component cursor within visible bounds. Entering a category
via the sidebar SHOULD move the component cursor to that category's first entry.

#### Scenario: Cursor clamped at list edges

- GIVEN focus on the component pane with the cursor on the first entry
- WHEN the user presses `up`
- THEN the cursor stays on the first entry
- AND pressing `down` repeatedly never moves past the last visible entry

#### Scenario: Sidebar navigation jumps component cursor to category start

- GIVEN focus on the sidebar and the cursor moved down one category
- WHEN focus returns to the component pane
- THEN the component cursor sits on the first component of the newly active category

### Requirement: Toggle Rules For Space

`space` MUST toggle the cursor component's selection only when the component is neither
required nor already applied; otherwise the key MUST have no effect. `a` selects all
visible-in-scope non-required components of the relevant category (`a`) or clears them
(`n`); in the sidebar it acts on the active category, in the component pane on the
cursor component's category. Required components MUST NOT be deselectable by any key.

#### Scenario: Space toggles an ordinary component

- GIVEN the cursor on a non-required, not-applied component currently unselected
- WHEN space is pressed
- THEN the component becomes selected (mark `x`)
- AND a second space press deselects it again

#### Scenario: Space ignored for required and applied components

- GIVEN the cursor on required component `base`
- WHEN space is pressed
- THEN `base` remains selected and cannot be toggled off
- GIVEN instead a cursor on an applied component
- WHEN space is pressed
- THEN its state does not change

#### Scenario: Category all/none skips required components

- GIVEN a category containing both ordinary and required components
- WHEN `n` is invoked for that category
- THEN every ordinary component in the category becomes deselected
- AND required components in the category remain selected

### Requirement: Search Filtering

`/` MUST enter search mode capturing typed characters into a query; `backspace` deletes
the last character; `enter` or `esc` exits search mode. While searching, the component
pane SHALL show only components whose label or category contains the query
(case-insensitive), and navigation/toggle keys operate on the filtered set. An empty
query matches everything.

#### Scenario: Query filters by label case-insensitively

- GIVEN search mode active with query matching some component labels
- WHEN the component list renders
- THEN only components whose label or category contains the query (case-insensitive)
  are visible
- AND clearing the query restores the full grouped list

#### Scenario: No matches shows empty result feedback

- GIVEN a query matching no component
- WHEN the list renders
- THEN a "no matches" message including the query is shown instead of entries
- AND `a`/`n`/`space` are no-ops while the visible set is empty

#### Scenario: Enter on empty result set does not open review

- GIVEN a query matching no component
- WHEN enter is pressed
- THEN the review screen does NOT open

### Requirement: Review Flow

`enter` on a non-empty visible set MUST open a review screen listing ONLY components
that are selected and not applied, grouped by category headers, with installed and
pending counts in the header. On review: `enter` or `y` submits the selection;
`esc` returns to the selection screen without submitting; `q` quits; `up`/`down` scroll
when content exceeds available height.

#### Scenario: Review lists only selected-not-applied grouped by category

- GIVEN applied component A, selected component B, and deselected component C
- WHEN the review opens
- THEN only B appears, under its category header
- AND neither A nor C appears

#### Scenario: Submit versus cancel

- GIVEN the review screen is open
- WHEN enter or y is pressed
- THEN the selection is submitted and the program proceeds to apply
- WHEN esc is pressed instead
- THEN the selection screen returns with the selection unchanged

#### Scenario: Empty review reports nothing to do

- GIVEN every selected component is already applied
- WHEN the review opens
- THEN it displays a "nothing to install" style message rather than rows

### Requirement: Viewport Keeps Footer Visible

When component rows exceed available height, the viewport MUST scroll to keep the
cursor row visible and MUST indicate more content above/below ("↑ more" / "↓ more")
while keeping the status line and help footer always rendered at the bottom.

#### Scenario: Long list scrolls with indicators

- GIVEN more component rows than fit in the terminal height
- WHEN the cursor moves beyond the visible window
- THEN the viewport shifts so the cursor row stays visible
- AND "more" indicators appear on the clipped edges
- AND the footer lines remain present as the final output lines
