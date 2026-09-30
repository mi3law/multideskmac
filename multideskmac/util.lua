local M = {}

-- This module's directory (works wherever multideskmac is installed or symlinked).
M.root = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
M.helper = M.root .. "/bin/deskhelper"

-- Timers are garbage-collected unless referenced; keep in-flight ones here.
local live = {}

-- Poll pred() every `interval` seconds until it returns a truthy value or `timeout` passes,
-- then call done(value) (nil on timeout).
function M.waitUntil(pred, timeout, done, interval)
  local deadline = hs.timer.secondsSinceEpoch() + timeout
  local t
  t = hs.timer.doEvery(interval or 0.05, function()
    local v = pred()
    if v or hs.timer.secondsSinceEpoch() > deadline then
      t:stop()
      live[t] = nil
      done(v or nil)
    end
  end)
  live[t] = true
end

-- hs.timer.doAfter that can't be garbage-collected before it fires.
function M.after(seconds, fn)
  local t
  t = hs.timer.doAfter(seconds, function()
    live[t] = nil
    fn()
  end)
  live[t] = true
  return t
end

function M.urlEncode(s)
  return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

return M
