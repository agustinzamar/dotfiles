-- Paneru configuration (hot-reloaded on save).
paneru.setup({
  options = {
    focus_follows_mouse = true,
    mouse_follows_focus = true,
  },
  padding = {
    top = 0, -- Paneru already reserves the native menu bar height.
  },
  bindings = {
    ["window focus west"] = "alt - h",
    ["window focus east"] = "alt - l",
    ["window resize"] = "alt - r",
    ["window center"] = "alt - c",
    ["window balance"] = "alt - b",
    ["window fullwidth"] = "alt - f",

    ["window nextdisplaysend"] = "alt + shift - d",

    ["window manage"] = "alt + ctrl - f",

    ["window grow"] = "alt - rightarrow",
    ["window shrink"] = "alt - leftarrow",

    ["quit"] = "ctrl + alt - q",
  },
})
