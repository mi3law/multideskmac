require("hs.ipc") -- enables the `hs` command-line tool (handy for debugging; optional)

multideskmac = require("multideskmac")
multideskmac.start({
  -- Start Hammerspoon at login. The "Launch at login" menu item overrides this default.
  launchAtLogin = true,

  chrome = {
    -- When a profile already has windows on some desktop:
    --   "newWindowOnItsDesktop" (go there, open another window), "focus" (just go there),
    --   "newWindowNewDesktop" (new window on an empty/new desktop).
    -- Changing it from the menu bar overrides this default.
    defaultMode = "newWindowOnItsDesktop",
    hotkey = { { "ctrl", "alt", "cmd" }, "p" }, -- profile picker
    launchers = true, -- ~/Applications/Chrome Profiles/Chrome – <name>.app
  },

  -- Clicking these apps' Dock icons on a desktop without their windows opens a new window here
  -- instead of jumping to another desktop. Hold any modifier while clicking for the usual jump.
  -- Value: true (use File > New Window), a menu path like { "File", "New Window" }, or a function.
  newWindowHere = {
    apps = {
      ["com.apple.finder"] = true, -- uses File > New Finder Window
    },
  },
})
