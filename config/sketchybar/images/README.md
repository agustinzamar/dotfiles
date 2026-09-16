# Provider logos for the SketchyBar usage plugin

White/coral 96px PNGs (transparent background, except OpenCode which ships
its own dark tile) rendered from the official brand SVGs below:

- `codex.*` — Codex terminal mark (white), provided by the user.
- `claude.*` — Claude starburst in brand coral `#D97757`, provided by
  the user.
- `opencode.*` — OpenCode tile, provided by the user.

Regenerate (requires `librsvg`):

```bash
rsvg-convert -w 96 -h 96 claude.svg -o claude.png
```
