-- Round profile avatars, optionally badged with the Chrome logo.
local M = {}

local function initialCircle(c, size, name)
  c:appendElements({
    type = "circle", action = "fill", radius = size * 0.44,
    fillColor = { red = 0.26, green = 0.52, blue = 0.96 },
  }, {
    type = "text", text = hs.styledtext.new(name:sub(1, 1):upper(), {
      font = { name = ".AppleSystemUIFontBold", size = size * 0.5 },
      color = { white = 1 }, paragraphStyle = { alignment = "center" },
    }),
    frame = { x = 0, y = size * 0.2, w = size, h = size * 0.7 },
  })
end

-- profile = { name, picture }; badge = draw the Chrome logo bottom-right.
function M.avatar(profile, size, badge)
  local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  local pic = profile.picture and hs.image.imageFromPath(profile.picture)
  local inset = badge and size * 0.06 or 0
  if pic then
    c:appendElements({
      type = "circle", action = "clip", radius = size / 2 - inset,
    }, {
      type = "image", image = pic, imageScaling = "scaleToFit",
      frame = { x = inset, y = inset, w = size - 2 * inset, h = size - 2 * inset },
    }, { type = "resetClip" })
  else
    initialCircle(c, size, profile.name)
  end
  if badge then
    local logo = hs.image.imageFromAppBundle("com.google.Chrome")
    if logo then
      c:appendElements({
        type = "image", image = logo,
        frame = { x = size * 0.54, y = size * 0.54, w = size * 0.44, h = size * 0.44 },
      })
    end
  end
  local img = c:imageFromCanvas()
  c:delete()
  return img
end

-- Menu bar icon: a 2x2 grid of desktops, one filled (like Mission Control's Spaces bar).
function M.menubarIcon()
  local c = hs.canvas.new({ x = 0, y = 0, w = 18, h = 18 })
  local cells = { { 1.5, 2.5 }, { 10, 2.5 }, { 1.5, 10 }, { 10, 10 } }
  for i, xy in ipairs(cells) do
    c:appendElements({
      type = "rectangle", action = i == 1 and "strokeAndFill" or "stroke",
      frame = { x = xy[1], y = xy[2], w = 6.5, h = 5.5 },
      roundedRectRadii = { xRadius = 1.2, yRadius = 1.2 },
      strokeColor = { white = 0 }, fillColor = { white = 0 }, strokeWidth = 1.2,
    })
  end
  local img = c:imageFromCanvas()
  c:delete()
  return img:template(true)
end

return M
