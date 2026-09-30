-- Tiny "Chrome – <Profile>.app" bundles so profiles can be launched from Spotlight, the Dock,
-- Raycast, etc. Each just hands the request to Hammerspoon via a hammerspoon:// URL.
local chrome = require("multideskmac.chrome")
local icons = require("multideskmac.icons")
local util = require("multideskmac.util")

local M = {}
local log = hs.logger.new("mdesk.lnc", "info")

M.folder = os.getenv("HOME") .. "/Applications/Chrome Profiles"
local ID_PREFIX = "local.multideskmac.chrome."
local VERSION = 2 -- bump when the bundle format changes, so existing launchers get rebuilt

local function sh(cmd)
  local out, ok = hs.execute(cmd)
  if not ok then log.e(cmd .. " -> " .. tostring(out)) end
  return ok
end

local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function bundleName(p) return "Chrome – " .. p.name .. ".app" end

local function build(p)
  local app = M.folder .. "/" .. bundleName(p)
  local contents = app .. "/Contents"
  sh(string.format("rm -rf %s && mkdir -p %s/MacOS %s/Resources", q(app), q(contents), q(contents)))

  hs.plist.write(contents .. "/Info.plist", {
    CFBundleName = "Chrome – " .. p.name,
    CFBundleDisplayName = "Chrome – " .. p.name,
    CFBundleIdentifier = ID_PREFIX .. p.dir:gsub("[^%w]", ""),
    CFBundleExecutable = "launch",
    CFBundleIconFile = "icon",
    CFBundlePackageType = "APPL",
    CFBundleVersion = "1",
    LSUIElement = true,
    MultiDeskMacProfileDirectory = p.dir,
    MultiDeskMacLauncherVersion = VERSION,
  })

  local url = "hammerspoon://multideskmac-chrome?profile=" .. util.urlEncode(p.dir)
  local script = contents .. "/MacOS/launch"
  local f = io.open(script, "w")
  f:write("#!/bin/sh\n# Opens the Chrome profile \"" .. p.name .. "\" on its own desktop (hold Option: this desktop).\n")
  f:write("exec /usr/bin/open -g '" .. url .. "'\n")
  f:close()
  sh("chmod +x " .. q(script))

  local png = contents .. "/Resources/icon.png"
  icons.avatar(p, 512, true):saveToFile(png)
  sh(string.format("sips -s format icns %s --out %s >/dev/null && rm %s",
    q(png), q(contents .. "/Resources/icon.icns"), q(png)))
  return app
end

local function upToDate(p)
  local info = hs.plist.read(M.folder .. "/" .. bundleName(p) .. "/Contents/Info.plist")
  return info and info.MultiDeskMacLauncherVersion == VERSION and info.MultiDeskMacProfileDirectory == p.dir
end

-- Create missing or outdated launchers (all of them with force) and remove ones for deleted
-- profiles. Current bundles are left alone so Dock items pointing at them keep working.
function M.sync(force)
  sh("mkdir -p " .. q(M.folder))
  local wanted = {}
  for _, p in ipairs(chrome.profiles()) do
    wanted[bundleName(p)] = true
    if force or not upToDate(p) then build(p) end
  end
  for file in hs.fs.dir(M.folder) do
    if file:match("%.app$") and not wanted[file] then
      local info = hs.plist.read(M.folder .. "/" .. file .. "/Contents/Info.plist")
      if info and tostring(info.CFBundleIdentifier):sub(1, #ID_PREFIX) == ID_PREFIX then
        sh("rm -rf " .. q(M.folder .. "/" .. file))
      end
    end
  end
  sh("touch " .. q(M.folder))
  log.i("launchers synced in " .. M.folder)
end

return M
