#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Native macOS Spaces indicator driven by Paneru state (no yabai dependency).
#
# Paneru knows every native Space it manages via `paneru query state --json`:
# each virtual-workspace row carries a `native_workspace_id`, and
# `.active.native_workspace_id` identifies the focused native Space. We group
# virtual rows by native id preserving first-appearance order: slot 1 shows a
# Work icon, slot 2 a Social icon (no text label), slots 3+ show a numeric
# label with no icon. The active position is highlighted; unused slots are
# hidden. Clicking a slot delegates to focus-native-space.sh with the 1-based
# position.
WORK_ICON=
SOCIAL_ICON=

native_spaces_update() {
    local state rows row slot_label icon_value label_value icon_on focused color
    local focus_script="$HOME/.config/sketchybar/plugins/focus-native-space.sh"
    local -a entries
    local slot

    if state=$(paneru query state --json 2>/dev/null); then
        # Validate the complete response before exposing labels or click targets.
        rows=$(jq -er '
            if type == "object" and (.virtual_workspaces | type == "array") then
                ([.virtual_workspaces[]
                    | select(type == "object" and (.native_workspace_id | type == "number"))]
                    | map(.native_workspace_id)) as $ids
                | (reduce $ids[] as $id ([]; if index($id) then . else . + [$id] end)
                    | .[:10]) as $natives
                | (.active.native_workspace_id // null) as $active
                | ($natives | index($active) // -1 | . + 1) as $active_pos
                | $natives
                | to_entries[]
                | "\(.key + 1)\t\(if .key + 1 == $active_pos then 1 else 0 end)"
            else
                error("Invalid paneru state")
            end
        ' <<< "$state" 2>/dev/null) || rows=""
    fi

    [[ -n "$rows" ]] && entries=("${(@f)rows}")
    for ((slot = 1; slot <= 10; slot++)); do
        if ((slot > ${#entries})); then
            sketchybar --set "native_space.$slot" drawing=off
            continue
        fi

        row="${entries[$slot]}"
        slot_label="${row%%$'\t'*}"
        focused="${row##*$'\t'}"
        case "$slot_label" in
        1) icon_value="$WORK_ICON"; label_value=""; icon_on=on ;;
        2) icon_value="$SOCIAL_ICON"; label_value=""; icon_on=on ;;
        *) icon_value=""; label_value="$slot_label"; icon_on=off ;;
        esac
        color=0x66494d64
        [[ "$focused" == 1 ]] && color=0xfff5a97f
        sketchybar --set "native_space.$slot" \
            drawing=on \
            icon.drawing="$icon_on" \
            icon="$icon_value" \
            label.drawing="$([[ -n "$label_value" ]] && echo on || echo off)" \
            label="$label_value" \
            background.color="$color" \
            click_script="${(q)focus_script} $slot_label"
    done
}

native_spaces_update
