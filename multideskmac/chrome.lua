-- Chrome profiles, each on its own desktop.
local spaces = require("multideskmac.spaces")
local util = require("multideskmac.util")

local M = {}
local log = hs.logger.new("mdesk.chr", "info")

local BUNDLE_ID = "com.google.Chrome"
local APP_NAME = "Google Chrome"
local USER_DATA = os.getenv("HOME") .. "/Library/Application Support/Google/Chrome"

-- What launching a profile does when it already has windows on some desktop.
M.MODES = {
  { id = "newWindowOnItsDesktop", title = "Open a new window on its desktop" },
  { id = "focus", title = "Jump to its desktop" },
  { id = "newWindowNewDesktop", title = "Open a new window on a new desktop" },
}
local SETTING_MODE = "multideskmac.chrome.mode"
M.defaultMode = "newWindowOnItsDesktop"

function M.mode() return hs.settings.get(SETTING_MODE) or M.defaultMode end
function M.setMode(id) hs.settings.set(SETTING_MODE, id) end

-- Also relocate profile windows that Chrome opens itself (its profile menu, "Open link as…").
local SETTING_AUTOPLACE = "multideskmac.chrome.autoPlace"
M.defaultAutoPlace = true
function M.autoPlace()
  local v = hs.settings.get(SETTING_AUTOPLACE)
  if v == nil then return M.defaultAutoPlace end
  return v
end
function M.setAutoPlace(on) hs.settings.set(SETTING_AUTOPLACE, on) end

---------------------------------------------------------------------------
-- Profiles

function M.profiles()
  local f = io.open(USER_DATA .. "/Local State")
  if not f then return {} end
  local state = hs.json.decode(f:read("a"))
  f:close()
  local cache = state and state.profile and state.profile.info_cache or {}
  local order = state.profile.profiles_order
  if not order then
    order = {}
    for dir in pairs(cache) do table.insert(order, dir) end
    table.sort(order)
  end
  local list = {}
  for _, dir in ipairs(order) do
    local info = cache[dir]
    if info then
      local pic = USER_DATA .. "/" .. dir .. "/" .. (info.gaia_picture_file_name or "Google Profile Picture.png")
      table.insert(list, {
        dir = dir,
        name = info.name ~= "" and info.name or dir,
        picture = hs.fs.attributes(pic) and pic or nil,
      })
    end
  end
  return list
end

function M.profile(dirOrName)
  for _, p in ipairs(M.profiles()) do
    if p.dir == dirOrName or p.name == dirOrName then return p end
  end
end

---------------------------------------------------------------------------
-- Which window belongs to which profile.
-- Chrome window IDs are stable while Chrome runs, so remember what we've identified.

local SETTING_REG = "multideskmac.chrome.windows"
local registry = hs.settings.get(SETTING_REG) or { pid = 0, windows = {} }

local function app() return hs.application.get(BUNDLE_ID) end

local function saveRegistry() hs.settings.set(SETTING_REG, registry) end

local function checkPid()
  local a = app()
  local pid = a and a:pid() or 0
  if registry.pid ~= pid then registry = { pid = pid, windows = {} } saveRegistry() end
  return pid
end

function M.remember(wid, dir)
  checkPid()
  if registry.windows[tostring(wid)] ~= dir then
    registry.windows[tostring(wid)] = dir
    saveRegistry()
  end
end

function M.profileOfWindowID(wid)
  checkPid()
  return registry.windows[tostring(wid)] or nil -- false = known not to be a profile window
end

-- Identify a window's profile from its accessibility title, which Chrome ends with
-- " - Google Chrome - <label>" when there are several profiles. The label is the profile name,
-- or "<Google account first name> (<profile name>)" when the two differ.
function M.profileFromTitle(title, profiles)
  local label = title and title:match(".* %- Google Chrome %- (.+)$")
  if not label then return nil end
  profiles = profiles or M.profiles()
  for _, p in ipairs(profiles) do
    if label == p.name then return p.dir end
  end
  for _, p in ipairs(profiles) do
    local suffix = "(" .. p.name .. ")"
    if label:sub(-#suffix) == suffix then return p.dir end
  end
end

-- Learn from the windows plain AX can see (the current desktop, often more). Cheap.
function M.learnVisible()
  local a, profiles = app(), nil
  for _, w in ipairs(a and a:allWindows() or {}) do
    local key = tostring(w:id())
    if not registry.windows[key] and w:isStandard() then
      profiles = profiles or M.profiles()
      local dir = M.profileFromTitle(w:title(), profiles)
      if dir then registry.windows[key] = dir end
    end
  end
end

-- Identify any Chrome windows we haven't seen yet, on every desktop. The helper reaches windows
-- on other desktops, which plain AX can't; known windows are skipped, so this is usually instant.
function M.learnAll(snap)
  local pid = checkPid()
  if pid == 0 then return end
  M.learnVisible()
  snap = snap or spaces.snapshot()
  if not snap then return end
  local unknown, alive = {}, {}
  for wid, w in pairs(snap.windows) do
    if w.pid == pid then
      alive[tostring(wid)] = true
      if registry.windows[tostring(wid)] == nil and spaces.isRealWindow(w) then
        table.insert(unknown, tostring(wid))
      end
    end
  end
  for wid in pairs(registry.windows) do
    if not alive[wid] then registry.windows[wid] = nil end
  end
  if #unknown > 0 then
    local out, ok = hs.execute(string.format("'%s' axwindows %d %s",
      util.helper, pid, table.concat(unknown, " ")))
    local res = ok and hs.json.decode(out)
    if type(res) ~= "table" or res.error then
      log.w("axwindows failed: " .. tostring(out))
    else
      local profiles = M.profiles()
      for _, w in ipairs(res.windows) do
        registry.windows[tostring(w.id)] = M.profileFromTitle(w.title, profiles) or false
      end
      for _, wid in ipairs(res.missing) do registry.windows[tostring(wid)] = false end
    end
  end
  saveRegistry()
end

-- Desktops holding a profile's windows, current desktop first.
function M.desktopsOf(dir, snap)
  snap = snap or spaces.snapshot()
  local current, seen, list = spaces.currentSpace(), {}, {}
  for wid, w in pairs(snap.windows) do
    if M.profileOfWindowID(wid) == dir and spaces.isRealWindow(w) then
      for _, sid in ipairs(w.spaces) do
        if not seen[sid] then
          seen[sid] = true
          table.insert(list, sid)
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if a == current or b == current then return a == current end
    return (spaces.desktopNumber(a, snap) or 99) < (spaces.desktopNumber(b, snap) or 99)
  end)
  return list
end

---------------------------------------------------------------------------
-- Opening windows

local function standardWindowIDs()
  local ids, a = {}, app()
  for _, w in ipairs(a and a:allWindows() or {}) do
    if w:isStandard() then ids[w:id()] = w end
  end
  return ids
end

local ours = {} -- window IDs opened by MultiDeskMac itself; never relocated

-- Open a new window of the profile on the current desktop; done(win or nil).
function M.openWindow(dir, done)
  done = done or function() end
  local before = standardWindowIDs()
  local task
  task = hs.task.new("/usr/bin/open", function() task = nil end, -- (keeps task referenced until exit)
    { "-na", APP_NAME, "--args", "--profile-directory=" .. dir, "--new-window" })
  task:start()
  util.waitUntil(function()
    for id, w in pairs(standardWindowIDs()) do
      if not before[id] then return w end
    end
  end, 8, function(win)
    if win then
      ours[win:id()] = true
      M.remember(win:id(), dir)
      win:focus()
    else
      log.w("no new Chrome window appeared for " .. dir)
    end
    done(win)
  end, 0.1)
end

-- Focus one of the profile's windows on the current desktop; returns true if it found one.
local function focusOnCurrentDesktop(dir)
  local a = app()
  for _, w in ipairs(a and a:visibleWindows() or {}) do
    if w:isStandard() and M.profileOfWindowID(w:id()) == dir then
      w:focus()
      return true
    end
  end
  return false
end

local busy = nil -- token of the launch in progress

-- Launch a profile following the mode setting. opts.here = open on the current desktop.
function M.launch(dirOrName, opts)
  opts = opts or {}
  local p = M.profile(dirOrName)
  if not p then return hs.alert.show("No Chrome profile named " .. tostring(dirOrName)) end
  if busy then return end
  local token = {}
  busy = token
  local function finish() if busy == token then busy = nil end end

  if opts.here then return M.openWindow(p.dir, finish) end

  local snap = spaces.snapshot()
  M.learnAll(snap)
  local mode = M.mode()
  local homes = M.desktopsOf(p.dir, snap)
  log.i(string.format("launch %s mode=%s homes=%s", p.name, mode, hs.inspect(homes)))

  if #homes > 0 and mode ~= "newWindowNewDesktop" then
    spaces.switchTo(homes[1], function()
      if mode == "focus" and focusOnCurrentDesktop(p.dir) then return finish() end
      M.openWindow(p.dir, finish)
    end)
  else
    spaces.gotoEmptyDesktop(nil, function(ok)
      if not ok then
        hs.alert.show("Couldn't switch desktops; opening here")
      end
      M.openWindow(p.dir, finish)
    end)
  end
  -- never stay stuck if a step silently fails
  hs.timer.doAfter(15, finish)
end

---------------------------------------------------------------------------
-- Windows Chrome opens by itself land on the current desktop. If another profile already lives
-- there, send the new window to its own desktop.

-- The window's tabs, and a draggable spot in its tab strip (just right of the "+" button).
-- Walks only Chrome's own UI, never web content.
function M.tabStrip(win)
  local info, frame = { tabs = {} }, win:frame()
  local function walk(el, depth)
    if depth > 12 then return end
    local role = el.AXRole
    if role == "AXWebArea" or role == "AXScrollArea" then return end
    if role == "AXTabGroup" then
      for _, t in ipairs(el.AXChildren or {}) do
        if t.AXSubrole == "AXTabButton" then table.insert(info.tabs, t.AXTitle or "") end
      end
      return
    end
    if role == "AXButton" and el.AXDescription == "New Tab" then info.newTab = el.AXFrame end
    for _, ch in ipairs(el.AXChildren or {}) do walk(ch, depth + 1) end
  end
  walk(hs.axuielement.windowElement(win), 0)
  if info.newTab then
    local f = info.newTab
    local x = f.x + f.w + 30
    if x < frame.x + frame.w - 40 then info.grab = { x = x, y = f.y + f.h / 2 } end
  end
  info.fresh = #info.tabs == 1 and info.tabs[1] == "New Tab"
  return info
end

-- Where a relocated window of `dir` should go: its home desktop (per mode), else an empty one,
-- else nil meaning "a new desktop".
local function destination(dir, from, snap)
  if M.mode() ~= "newWindowNewDesktop" then
    for _, sid in ipairs(M.desktopsOf(dir, snap)) do
      if sid ~= from then return sid end
    end
  end
  for _, sid in ipairs(spaces.desktops(nil, snap)) do
    if sid ~= from and spaces.isEmpty(sid, snap) then return sid end
  end
end

local warned = false
local function relocate(win, dir, from, snap, strip)
  local p = M.profile(dir)
  local target = destination(dir, from, snap)
  log.i(string.format("relocating %s: tabs=%s grab=%s target=%s", p.name, hs.inspect(strip.tabs),
    tostring(strip.grab ~= nil), tostring(target)))

  local function viaCarry(sid)
    spaces.carry(win, strip.grab, sid, function(ok)
      log.i(string.format("carried %s window to space %d: %s", p.name, sid, tostring(ok)))
      if ok then win:focus() end
    end)
  end

  if strip.grab and (target == nil or spaces.pathTo(target, snap)) then
    if target then return viaCarry(target) end
    -- need a new desktop first; its shortcut may not be on, so check again once it exists
    return spaces.create(nil, function(sid)
      if sid and spaces.pathTo(sid) then return viaCarry(sid) end
      if strip.fresh then
        win:close()
        return util.after(0.5, function() M.launch(dir) end)
      end
    end)
  end

  if strip.fresh then
    -- A blank New Tab window: closing it and opening the profile in the right place loses nothing.
    log.i("reopening fresh " .. p.name .. " window on its own desktop")
    win:close()
    return util.waitUntil(function() return not hs.window.get(win:id()) end, 2, function()
      M.launch(dir)
    end)
  end

  if not warned then
    warned = true
    hs.alert.show("MultiDeskMac can't move this " .. p.name .. " window: turn on the \"Switch to Desktop N\" "
      .. "shortcuts (System Settings → Keyboard → Keyboard Shortcuts → Mission Control)", 6)
  end
end

function M.onNewWindow(win)
  if not (win and win:isStandard()) or not M.autoPlace() then return end
  if busy or ours[win:id()] then return end
  local dir = M.profileFromTitle(win:title())
  if not dir then return end
  M.remember(win:id(), dir)
  if hs.eventtap.checkKeyboardModifiers().alt then return end -- ⌥: keep it here

  local snap = spaces.snapshot()
  M.learnAll(snap)
  local w = snap and snap.windows[win:id()]
  if not w then return end
  local from = w.spaces[1]
  for _, other in ipairs(snap.bySpace[from] or {}) do
    local od = other.id ~= win:id() and M.profileOfWindowID(other.id)
    if od and od ~= dir then
      log.i(string.format("%s window opened on a desktop with %s", dir, od))
      -- a brand-new window's tab strip takes a moment to appear in the AX tree
      return util.waitUntil(function()
        local ok, strip = pcall(M.tabStrip, win)
        if ok and #strip.tabs > 0 and strip.tabs[1] ~= "" then return strip end
      end, 2.5, function(strip)
        if not hs.window.get(win:id()) then return end -- closed meanwhile
        relocate(win, dir, from, snap, strip or M.tabStrip(win))
      end, 0.15)
    end
  end
end

-- Watch the running Chrome for new windows. `open -na` (ours or anyone's) briefly starts a second
-- Chrome process that hands off and exits, so only re-attach when the main process changes.
local function watchChrome()
  local a = app()
  local pid = a and a:pid()
  if M.observer and M.observerPid == pid then return end
  if M.observer then M.observer:stop() end
  M.observer, M.observerPid = nil, nil
  if not pid then return end
  local ok, obs = pcall(function()
    return hs.axuielement.observer.new(pid)
      :callback(function(_, el)
        local ok2, win = pcall(function() return el:asHSWindow() end)
        -- wait for the title (and so the profile label) to settle
        if ok2 and win then util.after(0.7, function() M.onNewWindow(win) end) end
      end)
      :addWatcher(hs.axuielement.applicationElement(a), "AXWindowCreated")
      :start()
  end)
  if ok then
    M.observer, M.observerPid = obs, pid
  else
    log.w("couldn't watch Chrome: " .. tostring(obs))
  end
end

---------------------------------------------------------------------------
-- Keep the registry current as windows appear and the user moves around.

function M.start()
  hs.timer.doAfter(1, function() M.learnAll() end)
  watchChrome()
  M.appWatcher = hs.application.watcher.new(function(_, event, appObj)
    local changed = event == hs.application.watcher.launched or event == hs.application.watcher.terminated
    if changed and appObj and appObj:bundleID() == BUNDLE_ID then
      util.after(2, watchChrome)
    end
  end):start()
  -- each desktop switch reveals that desktop's windows to plain AX
  M.spaceWatcher = hs.spaces.watcher.new(function()
    if M.learnTimer then M.learnTimer:stop() end
    M.learnTimer = hs.timer.doAfter(0.5, function() M.learnVisible() saveRegistry() end)
  end):start()
end

return M
