# MultiDeskMac

Make macOS desktops (Spaces) work the way you'd expect when you use lots of them.

- **Chrome profiles on their own desktops.** Launch a profile and it opens on its own desktop, creating one if needed. You no longer have to drag each profile's window over by hand. Hold **⌥** to open it on the current desktop instead.
- **"New window here" for Finder, or any app.** Clicking Finder's Dock icon on a desktop where it has no windows normally jumps you to a desktop where it does. Here it opens a new Finder window where you are. Hold any modifier while clicking to jump the old way.

MultiDeskMac is a [Hammerspoon](https://www.hammerspoon.org) module plus a tiny Swift helper. It is macOS-only. It needs no SIP changes and no Dock injection.

## Install

Requirements: macOS 13 or later (developed on macOS 15 Sequoia), [Hammerspoon](https://www.hammerspoon.org), and the Xcode Command Line Tools (for `swiftc`).

```bash
brew install --cask hammerspoon
git clone https://github.com/mi3law/multideskmac.git
cd multideskmac
./install.sh
```

`install.sh` does three things:

- builds the helper
- symlinks `multideskmac/` into `~/.hammerspoon/`
- creates `~/.hammerspoon/init.lua` from [`init.example.lua`](init.example.lua), or prints a snippet to paste into your existing config

Then give Hammerspoon Accessibility access in **System Settings → Privacy & Security → Accessibility**, and reload its config.

**Recommended:** turn on **System Settings → Keyboard → Keyboard Shortcuts… → Mission Control → "Switch to Desktop 1, 2, …"**. You can use any key combination; MultiDeskMac reads whichever you choose. Switching through those shortcuts should be smoother. Without them, MultiDeskMac clicks the desktop in Mission Control, which takes about a second and briefly shows Mission Control.

## Use

### Chrome profiles

There are several ways to launch a profile:

| Where | How |
| --- | --- |
| Spotlight, Raycast, Dock | `Chrome – <profile>` apps in `~/Applications/Chrome Profiles/` (one per profile, with the profile's avatar as the icon) |
| Hotkey | **⌃⌥⌘P** opens a picker that shows which desktop each profile is on |
| Menu bar | The desktop-grid icon lists your profiles |
| URL | `open -g "hammerspoon://multideskmac-chrome?profile=Profile%201"` (add `&here=1` for the current desktop) |

Holding **⌥** while launching opens the profile on the current desktop.

When a profile **isn't open**, it opens on an empty desktop. That's the current desktop if it's empty, else the nearest empty one, else a new desktop.

When a profile **is already open** somewhere, the menu bar setting *If the profile is already open* decides what happens:

- **Open a new window on its desktop** (default)
- **Jump to its desktop** and focus its window
- **Open a new window on a new desktop**

### New window here

Configured apps (Finder by default) open a new window on the current desktop when you click their Dock icon and all their windows are on other desktops. Add more apps in `init.lua`:

```lua
newWindowHere = {
  apps = {
    ["com.apple.finder"] = true,                               -- built in: File > New Finder Window
    ["com.example.Editor"] = true,                             -- File > New Window
    ["com.example.Other"] = { "Window", "New Main Window" },   -- any menu path
    ["com.example.Custom"] = function(app) --[[ ... ]] end,    -- or any function
  },
},
```

`true` uses the app's **File → New Window** menu item.

### Settings

Everything is in `~/.hammerspoon/init.lua`; see [`init.example.lua`](init.example.lua). The menu bar lets you change the "already open" behavior and toggle **Launch at login** (on by default). The menu bar choices override `init.lua`.

## How it works

- **Seeing desktops and windows.** Hammerspoon's window APIs only see the current desktop, so `deskhelper` (Swift) reads every desktop and every window's desktop through SkyLight's read-only calls. These are the private window-server APIs tools like yabai use. It never modifies window-server state.
- **Telling profiles apart.** Chrome ends window titles with ` - Google Chrome - <profile label>` when several profiles exist. `deskhelper` reads the titles of windows on *other* desktops through Accessibility elements built from remote tokens (the technique [AltTab](https://github.com/lwouis/alt-tab-macos) uses). The results are cached per window, so lookups are usually instant.
- **Switching and creating desktops.** There's no public API for either. MultiDeskMac presses your "Switch to Desktop N" shortcut if it's on. Otherwise it drives Mission Control through Accessibility, which is also the only way to add a desktop.
- **Opening a profile.** It switches first, then runs `open -na "Google Chrome" --args --profile-directory=… --new-window`. New windows land on the current desktop.
- **Dock clicks.** An event tap hit-tests clicks near the Dock. When a click would jump to another desktop, it swallows the click and creates a window here instead.

## Limitations

- It relies on private and undocumented macOS behavior (SkyLight, Mission Control's Accessibility tree), so a macOS update could break it.
- Profile detection expects Chrome's English window-title format and the stable Chrome channel (`com.google.Chrome`).
- Only Dock clicks get "new window here". Cmd-Tab and Spotlight keep the normal jump, which is usually what you want there.
- It works with multiple displays in principle, but has only been tested on a single display.

## Uninstall

1. Remove the `multideskmac.start{…}` block from `~/.hammerspoon/init.lua`.
2. Run this, then reload Hammerspoon:
   ```bash
   rm ~/.hammerspoon/multideskmac
   rm -rf ~/Applications/Chrome\ Profiles
   ```
3. Turn off **Launch at login** first if you want Hammerspoon to stop starting at login.

## License

[MIT](LICENSE)
