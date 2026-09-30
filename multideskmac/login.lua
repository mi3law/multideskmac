-- Start Hammerspoon (and so MultiDeskMac) at login. Config sets the default; the menu toggle overrides it.
local M = {}
local KEY = "multideskmac.launchAtLogin"

M.default = true

function M.enabled()
  local v = hs.settings.get(KEY)
  if v == nil then return M.default end
  return v
end

function M.set(on)
  hs.settings.set(KEY, on)
  hs.autoLaunch(on)
end

function M.apply()
  if hs.autoLaunch() ~= M.enabled() then hs.autoLaunch(M.enabled()) end
end

return M
