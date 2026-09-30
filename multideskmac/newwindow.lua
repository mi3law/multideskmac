-- "New window here": clicking an app's Dock icon while its windows are all on other desktops
-- normally jumps you to one of them. For configured apps, open a new window on this desktop instead.
-- Any modifier key held on the click (or Cmd-Tab) keeps the normal jump.
local spaces = require("multideskmac.spaces")

local M = {}
local log = hs.logger.new("mdesk.new", "info")
local types = hs.eventtap.event.types

-- How to make a new window, per bundle ID. A function, or a menu path for selectMenuItem.
M.handlers = {
  ["com.apple.finder"] = { "File", "New Finder Window" },
}
M.apps = { ["com.apple.finder"] = true }

-- Does the app have windows on other desktops but none on this one?
local function wouldJump(app)
  local snap = spaces.snapshot()
  if not snap then return false end
  local current, here, elsewhere = spaces.currentSpace(), false, false
  for _, w in pairs(snap.windows) do
    if w.pid == app:pid() and spaces.isRealWindow(w) then
      for _, sid in ipairs(w.spaces) do
        if sid == current then here = true else elsewhere = true end
      end
    end
  end
  return elsewhere and not here
end

function M.newWindowHere(bundleID)
  local app = hs.application.get(bundleID)
  if not app then return hs.application.launchOrFocusByBundleID(bundleID) end
  local handler = M.handlers[bundleID]
  if type(handler) == "function" then
    handler(app)
  else
    local ok = app:selectMenuItem(handler or { "File", "New Window" })
    if not ok then app:selectMenuItem("New Window") end
  end
  -- The new window is on this desktop, so activating the app no longer jumps away.
  hs.timer.doAfter(0.15, function() app:activate() end)
end

-- Only clicks near the Dock's screen edge get an (AX) hit-test, so ordinary clicks stay cheap.
-- (An auto-hidden Dock reports an off-screen frame until it slides in, so its frame can't be cached.)
local DOCK_BAND = 160
local dockEdge = "bottom"

local function nearDock(p)
  local s = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = s:fullFrame()
  if dockEdge == "left" then return p.x - f.x < DOCK_BAND end
  if dockEdge == "right" then return f.x + f.w - p.x < DOCK_BAND end
  return f.y + f.h - p.y < DOCK_BAND
end

local function bundleIDOfDockItem(el)
  local url = el.AXURL
  local path = type(url) == "table" and (url.filePath or url.url) or url
  if type(path) ~= "string" then return nil end
  path = path:gsub("^file://", ""):gsub("%%20", " "):gsub("/$", "")
  local info = hs.application.infoForBundlePath(path)
  return info and info.CFBundleIdentifier
end

local swallowMouseUp = false

local function onClick(e)
  if e:getType() == types.leftMouseUp then
    if swallowMouseUp then
      swallowMouseUp = false
      return true
    end
    return false
  end
  local flags = e:getFlags()
  if flags.cmd or flags.alt or flags.ctrl or flags.shift then return false end
  local pos = e:location()
  if not nearDock(pos) then return false end

  local el = hs.axuielement.systemElementAtPosition(pos)
  if not el or el.AXSubrole ~= "AXApplicationDockItem" then return false end
  local bundleID = bundleIDOfDockItem(el)
  if not (bundleID and M.apps[bundleID]) then return false end
  local app = hs.application.get(bundleID)
  if not (app and wouldJump(app)) then return false end

  log.i("dock click on " .. bundleID .. ": new window on this desktop")
  swallowMouseUp = true
  hs.timer.doAfter(0, function() M.newWindowHere(bundleID) end)
  return true
end

function M.start(config)
  config = config or {}
  for id, v in pairs(config.apps or {}) do
    M.apps[id] = v and true or nil
    if type(v) == "table" or type(v) == "function" then M.handlers[id] = v end
  end
  local orientation = hs.execute("defaults read com.apple.dock orientation 2>/dev/null")
  dockEdge = orientation:match("left") or orientation:match("right") or "bottom"
  M.tap = hs.eventtap.new({ types.leftMouseDown, types.leftMouseUp }, onClick):start()
  -- macOS disables event taps that are ever slow to respond; turn it back on if that happens.
  M.watchdog = hs.timer.doEvery(5, function()
    if not M.tap:isEnabled() then
      log.w("event tap was disabled; re-enabling")
      M.tap:start()
    end
  end)
end

return M
