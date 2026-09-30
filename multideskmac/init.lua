-- MultiDeskMac: better use of macOS desktops (Spaces).
--   * Chrome profiles open on their own desktop (menu bar, hotkey picker, Spotlight launchers,
--     hammerspoon://multideskmac-chrome?profile=<dir>[&here=1]).
--   * Dock clicks on apps like Finder open a window on this desktop instead of jumping away.
local M = {}

function M.start(config)
  config = config or {}
  local chrome = require("multideskmac.chrome")
  local menubar = require("multideskmac.menubar")
  local cc = config.chrome or {}

  local login = require("multideskmac.login")
  if config.launchAtLogin ~= nil then login.default = config.launchAtLogin end
  login.apply()

  if cc.defaultMode then chrome.defaultMode = cc.defaultMode end
  chrome.start()
  menubar.start()

  hs.urlevent.bind("multideskmac-chrome", function(_, params)
    local here = params.here == "1" or hs.eventtap.checkKeyboardModifiers().alt
    chrome.launch(params.profile, { here = here })
  end)

  if cc.hotkey then
    M.chromeHotkey = hs.hotkey.bind(cc.hotkey[1], cc.hotkey[2], menubar.showChooser)
  end

  if cc.launchers ~= false then
    hs.timer.doAfter(2, function() require("multideskmac.launchers").sync() end)
  end

  if config.newWindowHere then
    require("multideskmac.newwindow").start(config.newWindowHere)
  end
end

return M
