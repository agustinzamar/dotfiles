-- Paneru configuration (hot-reloaded on save).
paneru.setup {
  options = {
    focus_follows_mouse = true,
    mouse_follows_focus = true,
  },
  padding = {
    top = 16,
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

    ["window virtualnum 1"] = "alt - 1",
    ["window virtualnum 2"] = "alt - 2",
    ["window virtualnum 3"] = "alt - 3",
    ["window virtualnum 4"] = "alt - 4",
    ["window virtualnum 5"] = "alt - 5",
    ["window virtualnum 6"] = "alt - 6",
    ["window virtualnum 7"] = "alt - 7",
    ["window virtualnum 8"] = "alt - 8",
    ["window virtualnum 9"] = "alt - 9",

    ["window virtualmovenum 1"] = "alt + shift - 1",
    ["window virtualmovenum 2"] = "alt + shift - 2",
    ["window virtualmovenum 3"] = "alt + shift - 3",
    ["window virtualmovenum 4"] = "alt + shift - 4",
    ["window virtualmovenum 5"] = "alt + shift - 5",
    ["window virtualmovenum 6"] = "alt + shift - 6",
    ["window virtualmovenum 7"] = "alt + shift - 7",
    ["window virtualmovenum 8"] = "alt + shift - 8",
    ["window virtualmovenum 9"] = "alt + shift - 9",

    ["quit"] = "ctrl + alt - q",
  }
}
