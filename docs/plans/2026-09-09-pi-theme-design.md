# Pi Theme Fix Design

## Implementation goal

Track the live Pi settings and custom terminal theme in dotfiles. Use the terminal background `#24273A` for Pi panels and pending tool output so the prompt matches Ghostty.

## Architecture

`install/links.sh` remains the single link map. One `pi` name covers both normal symlinks and is gated by the existing `ai` component. The tracked settings file replaces the live Pi settings file through an intentional user-authorized symlink. No backup is created for that replacement.

## Exact files

| File | Change |
| --- | --- |
| `config/pi/settings.json` | Copy the live settings and select `Gentleman-Cute-Terminal`. |
| `config/pi/themes/Gentleman-Cute-Terminal.json` | Copy `Gentleman-Cute.json`, rename it, and set `bgPanel`, `bgElement`, `bgSubtle`, and `toolPendingBg` to `#24273A`. |
| `install/links.sh` | Add the settings and theme symlink rows under the `ai` component. |
| `docs/plans/2026-09-09-pi-theme-design.md` | Record the implementation and verification plan. |

## Verification

```bash
python3 -m json.tool config/pi/settings.json >/dev/null
python3 -m json.tool config/pi/themes/Gentleman-Cute-Terminal.json >/dev/null
bash -n install/links.sh
```

The verification must also confirm that both `pi` rows use empty mode and requirement/OS fields, and that the live settings and theme paths resolve through symlinks into `~/dotfiles`.
