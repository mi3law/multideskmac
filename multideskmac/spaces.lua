-- Desktop (Space) queries and actions: which windows live where, switching, creating.
local util = require("multideskmac.util")

local M = {}
local log = hs.logger.new("mdesk.sp", "info")
local HELPER = util.helper

-- Windows smaller than this are Chrome bubbles, invisible helpers, etc. They don't make a desktop "occupied".
local MIN_W, MIN_H = 200, 150

-- Snapshot of every desktop and every normal window on it, from the Swift helper.
-- Returns { displays = { {uuid, current, spaces = {id...}} }, windows = { [id] = {...} },
--           bySpace = { [spaceID] = {win...} } }
function M.snapshot()
  local out, ok = hs.execute(string.format("'%s' state", HELPER))
  local data = ok and hs.json.decode(out)
  if not data then
    log.e("deskhelper failed: " .. tostring(out))
    return nil
  end
  local snap = { displays = {}, windows = {}, bySpace = {} }
  for _, d in ipairs(data.displays) do
    local spaces = {}
    for _, s in ipairs(d.spaces) do
      if s.type == 0 then table.insert(spaces, s.id) end -- user desktops only, no full-screen apps
      snap.bySpace[s.id] = {}
    end
    table.insert(snap.displays, { uuid = d.uuid, current = d.current, spaces = spaces })
  end
  for _, w in ipairs(data.windows) do
    snap.windows[w.id] = w
    for _, sid in ipairs(w.spaces) do
      if snap.bySpace[sid] then table.insert(snap.bySpace[sid], w) end
    end
  end
  return snap
end

-- The screen the user is working on: the focused window's, else the one under the mouse.
function M.activeScreen()
  local win = hs.window.focusedWindow()
  return (win and win:screen()) or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
end

function M.currentSpace(screen)
  return hs.spaces.activeSpaceOnScreen(screen or M.activeScreen())
end

-- User desktops on a screen, in Mission Control order.
function M.desktops(screen, snap)
  snap = snap or M.snapshot()
  local uuid = (screen or M.activeScreen()):getUUID()
  for _, d in ipairs(snap.displays) do
    if d.uuid == uuid or #snap.displays == 1 then return d.spaces end
  end
  return {}
end

-- "Desktop N" number as macOS uses it for the Switch to Desktop N shortcuts (counted across displays).
function M.desktopNumber(spaceID, snap)
  snap = snap or M.snapshot()
  local n = 0
  for _, d in ipairs(snap.displays) do
    for _, sid in ipairs(d.spaces) do
      n = n + 1
      if sid == spaceID then return n end
    end
  end
end

function M.isRealWindow(w)
  return w.alpha > 0 and w.w >= MIN_W and w.h >= MIN_H
end

function M.isEmpty(spaceID, snap)
  for _, w in ipairs(snap.bySpace[spaceID] or {}) do
    if M.isRealWindow(w) then return false end
  end
  return true
end

-- An empty desktop to reuse, preferring the current one, then the nearest one to the right.
function M.findEmptyDesktop(screen, snap)
  snap = snap or M.snapshot()
  local current = M.currentSpace(screen)
  if M.isEmpty(current, snap) then return current end
  local list, start = M.desktops(screen, snap), 1
  for i, sid in ipairs(list) do if sid == current then start = i end end
  for off = 1, #list do
    local sid = list[((start - 1 + off) % #list) + 1]
    if M.isEmpty(sid, snap) then return sid end
  end
end

-- macOS keyboard shortcuts (System Settings → Keyboard Shortcuts → Mission Control), if turned on.
local SYMBOLIC_HOTKEYS = os.getenv("HOME") .. "/Library/Preferences/com.apple.symbolichotkeys.plist"
local MOD_FLAGS = { shift = 0x20000, ctrl = 0x40000, alt = 0x80000, cmd = 0x100000, fn = 0x800000 }
local MOVE_LEFT, MOVE_RIGHT = 79, 81 -- "Move left/right a space"

local function symbolicHotkey(id)
  local plist = hs.plist.read(SYMBOLIC_HOTKEYS)
  local entry = plist and plist.AppleSymbolicHotKeys and plist.AppleSymbolicHotKeys[tostring(id)]
  if not (entry and entry.enabled and entry.value and entry.value.parameters) then return nil end
  local keycode, flags = entry.value.parameters[2], entry.value.parameters[3]
  local mods = {}
  for name, bit in pairs(MOD_FLAGS) do
    if flags & bit ~= 0 then table.insert(mods, name) end
  end
  return { mods = mods, keycode = keycode }
end

-- "Switch to Desktop N"
function M.desktopShortcut(n)
  if n < 1 or n > 16 then return nil end
  return symbolicHotkey(117 + n)
end

function M.shortcutsEnabled()
  return M.desktopShortcut(1) ~= nil
end

local function pressShortcut(sc)
  hs.eventtap.event.newKeyEvent(sc.mods, sc.keycode, true):post()
  hs.eventtap.event.newKeyEvent(sc.mods, sc.keycode, false):post()
end

-- Switch to a desktop, then call done(ok). Uses the keyboard shortcut when enabled (fast, smooth),
-- otherwise clicks the desktop in Mission Control.
function M.switchTo(spaceID, done)
  done = done or function() end
  if hs.spaces.focusedSpace() == spaceID then return done(true) end
  local sc = M.desktopShortcut(M.desktopNumber(spaceID) or 0)
  if sc then
    pressShortcut(sc)
  else
    local ok, err = hs.spaces.gotoSpace(spaceID)
    if not ok then
      log.e("gotoSpace failed: " .. tostring(err))
      return done(false)
    end
  end
  util.waitUntil(function() return hs.spaces.focusedSpace() == spaceID end, 3, function(ok)
    if not ok then log.w("timed out switching to space " .. spaceID) end
    -- let the slide animation settle, so new windows land on the new desktop
    hs.timer.doAfter(0.25, function() done(ok) end)
  end)
end

-- Key presses that get from the current desktop to spaceID: "Switch to Desktop N" if on,
-- else repeated "Move left/right a space". nil if neither is turned on.
function M.pathTo(spaceID, snap)
  snap = snap or M.snapshot()
  local n, cur = M.desktopNumber(spaceID, snap), M.desktopNumber(M.currentSpace(), snap)
  if not (n and cur) then return nil end
  local direct = M.desktopShortcut(n)
  if direct then return { direct } end
  local arrow = symbolicHotkey(n > cur and MOVE_RIGHT or MOVE_LEFT)
  if not arrow then return nil end
  local presses = {}
  for _ = 1, math.abs(n - cur) do table.insert(presses, arrow) end
  return presses
end

-- Move a window to another desktop the only way macOS still allows without SIP changes: hold it by
-- its title bar (grab = a draggable point) while switching desktops with the keyboard shortcut.
-- Takes you along to that desktop. done(ok).
function M.carry(win, grab, spaceID, done)
  local presses = M.pathTo(spaceID)
  if not presses then return done(false) end
  local T, mouse = hs.eventtap.event.types, hs.mouse.absolutePosition()
  local held = { x = grab.x + 3, y = grab.y }
  hs.eventtap.event.newMouseEvent(T.leftMouseDown, grab):post()
  util.after(0.08, function()
    hs.eventtap.event.newMouseEvent(T.leftMouseDragged, held):post()
    local i = 0
    local function nextPress()
      i = i + 1
      if i > #presses then
        return util.waitUntil(function() return hs.spaces.focusedSpace() == spaceID end, 3, function()
          util.after(0.3, function()
            hs.eventtap.event.newMouseEvent(T.leftMouseUp, held):post()
            hs.mouse.absolutePosition(mouse)
            util.after(0.2, function()
              local on = hs.spaces.windowSpaces(win) or {}
              done(on[1] == spaceID)
            end)
          end)
        end)
      end
      local before = hs.spaces.focusedSpace()
      pressShortcut(presses[i])
      util.waitUntil(function() return hs.spaces.focusedSpace() ~= before end, 2, function()
        util.after(0.25, nextPress)
      end)
    end
    util.after(0.15, nextPress)
  end)
end

-- Create a desktop at the end of the screen's list without switching to it; done(spaceID or nil).
function M.create(screen, done)
  screen = screen or M.activeScreen()
  local before = {}
  for _, sid in ipairs(hs.spaces.spacesForScreen(screen) or {}) do before[sid] = true end
  local ok, err = hs.spaces.addSpaceToScreen(screen, true)
  if not ok then
    log.e("addSpaceToScreen failed: " .. tostring(err))
    return done(nil)
  end
  util.waitUntil(function()
    for _, sid in ipairs(hs.spaces.spacesForScreen(screen) or {}) do
      if not before[sid] then return sid end
    end
  end, 2, function(newID)
    -- let Mission Control finish closing before anything else happens
    util.after(0.6, function() done(newID) end)
  end)
end

-- Create a desktop at the end of the screen's list and switch to it; done(ok, spaceID).
function M.createAndGoto(screen, done)
  screen = screen or M.activeScreen()
  local before = {}
  for _, sid in ipairs(hs.spaces.spacesForScreen(screen) or {}) do before[sid] = true end
  local ok, err = hs.spaces.addSpaceToScreen(screen, false) -- keep Mission Control open for gotoSpace
  if not ok then
    log.e("addSpaceToScreen failed: " .. tostring(err))
    hs.spaces.closeMissionControl()
    return done(false)
  end
  util.waitUntil(function()
    for _, sid in ipairs(hs.spaces.spacesForScreen(screen) or {}) do
      if not before[sid] then return sid end
    end
  end, 2, function(newID)
    if not newID then
      hs.spaces.closeMissionControl()
      return done(false)
    end
    local ok2, err2 = hs.spaces.gotoSpace(newID)
    if not ok2 then
      log.e("gotoSpace(new) failed: " .. tostring(err2))
      hs.spaces.closeMissionControl()
      return done(false)
    end
    util.waitUntil(function() return hs.spaces.focusedSpace() == newID end, 3, function(arrived)
      hs.timer.doAfter(0.25, function() done(arrived ~= nil, newID) end)
    end)
  end)
end

-- Go to an empty desktop (reusing one if possible, else creating one); done(ok, spaceID).
function M.gotoEmptyDesktop(screen, done)
  screen = screen or M.activeScreen()
  local empty = M.findEmptyDesktop(screen)
  if empty then
    M.switchTo(empty, function(ok) done(ok, empty) end)
  else
    M.createAndGoto(screen, done)
  end
end

return M
