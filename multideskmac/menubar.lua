-- Menu bar menu and hotkey picker for Chrome profiles.
local chrome = require("multideskmac.chrome")
local spaces = require("multideskmac.spaces")
local icons = require("multideskmac.icons")

local M = {}

local GRAY = { white = 0.5 }

local function where(dir, snap)
  local nums = {}
  for _, sid in ipairs(chrome.desktopsOf(dir, snap)) do
    table.insert(nums, tostring(spaces.desktopNumber(sid, snap)))
  end
  if #nums == 0 then return nil end
  return (#nums == 1 and "Desktop " or "Desktops ") .. table.concat(nums, ", ")
end

local avatarCache = {}
local function avatar(p)
  avatarCache[p.dir] = avatarCache[p.dir] or icons.avatar(p, 32, false):setSize({ w = 16, h = 16 })
  return avatarCache[p.dir]
end

local function buildMenu()
  chrome.learnAll()
  local snap = spaces.snapshot()
  local items = {
    { title = "Chrome profiles", disabled = true },
  }
  for _, p in ipairs(chrome.profiles()) do
    local loc = where(p.dir, snap)
    local title = hs.styledtext.new(p.name)
    if loc then title = title .. hs.styledtext.new("    " .. loc, { color = GRAY }) end
    table.insert(items, {
      title = title,
      image = avatar(p),
      fn = function(mods) chrome.launch(p.dir, { here = mods.alt }) end,
    })
  end
  table.insert(items, { title = "Hold ⌥ to open on this desktop", disabled = true })
  table.insert(items, { title = "-" })

  local modeItems = {}
  for _, m in ipairs(chrome.MODES) do
    table.insert(modeItems, {
      title = m.title, checked = chrome.mode() == m.id,
      fn = function() chrome.setMode(m.id) end,
    })
  end
  table.insert(items, { title = "If the profile is already open", menu = modeItems })

  local switching = spaces.shortcutsEnabled()
    and "Switching desktops: keyboard shortcuts"
    or "Switching desktops: Mission Control (slower)"
  table.insert(items, { title = switching, disabled = true })
  if not spaces.shortcutsEnabled() then
    table.insert(items, {
      title = "Enable faster switching…",
      fn = function()
        hs.dialog.blockAlert("Faster desktop switching",
          "Turn on System Settings → Keyboard → Keyboard Shortcuts… → Mission Control → "
            .. "\"Switch to Desktop 1\", \"Switch to Desktop 2\", … (any key combo works; "
            .. "MultiDeskMac reads whatever you choose). Without them, MultiDeskMac clicks desktops in Mission Control.",
          "Open Keyboard Settings", "Later")
        hs.execute("open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension'")
      end,
    })
  end
  table.insert(items, { title = "-" })
  local login = require("multideskmac.login")
  table.insert(items, {
    title = "Launch at login", checked = login.enabled(),
    fn = function() login.set(not login.enabled()) end,
  })
  table.insert(items, { title = "Rebuild Spotlight launchers", fn = function()
    require("multideskmac.launchers").sync(true)
    hs.alert.show("Launchers updated")
  end })
  table.insert(items, { title = "Reload Hammerspoon config", fn = hs.reload })
  return items
end

M.buildMenu = buildMenu

function M.start()
  M.bar = hs.menubar.new(true, "multideskmac")
  M.bar:setIcon(icons.menubarIcon(), true)
  M.bar:setTooltip("MultiDeskMac — Chrome profiles on their own desktops")
  M.bar:setMenu(buildMenu)
end

-- Spotlight-style picker. Return: own desktop. ⌥-Return: this desktop.
function M.showChooser()
  chrome.learnAll()
  local snap = spaces.snapshot()
  local choices = {}
  for _, p in ipairs(chrome.profiles()) do
    table.insert(choices, {
      text = p.name,
      subText = where(p.dir, snap) or "Not open",
      image = avatar(p),
      dir = p.dir,
    })
  end
  if not M.chooser then
    M.chooser = hs.chooser.new(function(choice)
      if choice then
        chrome.launch(choice.dir, { here = hs.eventtap.checkKeyboardModifiers().alt })
      end
    end)
    M.chooser:placeholderText("Chrome profile   (⌥↩ opens on this desktop)")
  end
  M.chooser:choices(choices)
  M.chooser:query(nil)
  M.chooser:show()
end

return M
