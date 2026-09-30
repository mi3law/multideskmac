# MultiDeskMac: dev notes

Hammerspoon module (`multideskmac/`, Lua 5.4) and a Swift helper (`multideskmac/helper/deskhelper.swift`).
`install.sh` builds the helper into `multideskmac/bin/` (gitignored) and symlinks `multideskmac/` into
`~/.hammerspoon/`, so edits here take effect on a Hammerspoon config reload.

## Layout
- `init.lua`: `start(config)` wires everything up
- `spaces.lua`: desktop queries, switching (shortcut or Mission Control), creating desktops
- `chrome.lua`: profiles, window→profile registry, launch modes, relocating windows Chrome opens itself
- `newwindow.lua`: Dock-click interception
- `menubar.lua`, `launchers.lua`, `icons.lua`, `login.lua`, `util.lua`

## Testing against the live system
- `init.lua` loads `hs.ipc`, so `hs -c '<lua>'` runs code inside Hammerspoon. The `hs` client hangs
  while Hammerspoon is busy ("hs.ipc … already recursing, refusing request", e.g. during Mission
  Control automation), so wrap it: `perl -e 'alarm shift; exec @ARGV' 20 hs -c '...'`. For long flows,
  start them with `hs.timer.doAfter` and read the results back in a later call.
- Reload: `hs -c 'hs.timer.doAfter(0.2, hs.reload)'` (a direct `hs.reload()` kills the IPC reply).
- `deskhelper state` needs no permissions. `deskhelper axwindows` needs Accessibility and must be run
  *from Hammerspoon* (`hs.execute` / `hs.task`) to inherit its grant.
- Everything in Hammerspoon runs on the main thread: keep `hs.execute` calls short, and use
  `util.waitUntil` or timers for anything that waits.
- An auto-hidden Dock can't be revealed by synthetic mouse moves, so Dock clicks need a real click to test.

## Gotchas
- `goto` is a reserved word in Lua 5.4.
- `hs.spaces.moveWindowToSpace` returns true but does nothing on macOS 15. `spaces.carry` (title-bar
  drag plus a switch shortcut) is the only working way to move a window, and it needs the user's
  shortcuts turned on.
- `open -na "Google Chrome"` starts a short-lived second Chrome process that hands off and exits. App
  watchers see it as a Chrome launch, so don't re-point observers at it.
- Chrome's AX element IDs grow over its lifetime (thousands+). `axwindows` scans remote tokens until it
  has found the requested windows, within a 1.5 s budget. Results are cached in hs.settings.
- Launcher bundles carry `MultiDeskMacLauncherVersion`; bump `VERSION` in `launchers.lua` when the
  bundle format changes so existing launchers are rebuilt.
