local install = dofile("party_icons.lua")
local art = dofile("data/dex_art.lua")
for _, gen1 in ipairs({true, false}) do
  local entries = {BULBASAUR = "NATIVE"}
  local registry = {}
  function registry:get(id) return entries[id] end
  function registry:register(id, entry)
    assert(not entries[id], "duplicate icon " .. id)
    entries[id] = entry
  end
  function registry:override(id, entry)
    assert(entries[id], "override of missing icon " .. id)
    entries[id] = entry
  end
  local shader, draws, fail = "original-shader", 0, false
  love = {graphics = {
    getShader = function() return shader end,
    setShader = function(value) shader = value end,
  }}
  local menu = {drawIcon = function(owner, mon)
    draws = draws + 1
    if not mon.isEgg and art[mon.species] then
      assert(shader == nil, "modern art is palette-shaded")
      if not gen1 then assert(owner.palettes == nil) end
    else
      assert(shader == "original-shader")
    end
    if fail then error("test draw failure") end
    return "drawn"
  end}
  local module = gen1 and "src.ui.PartyMenu" or "src.ui.gen2.PartyMenu"
  package.loaded[module] = menu
  local ready
  local mod = {
    content = {icons = registry, pokemon = {get = function(_, id) return art[id] end}},
    assets = {path = function(_, path) return "mods/test/" .. path end},
    events = {on = function(_, event, fn) assert(event == "game.ready"); ready = fn end},
  }
  install(mod, art, 1025, gen1)
  local count = 0
  for species, row in pairs(art) do
    count = count + 1
    local entry = entries[species]
    if not gen1 then
      assert(entry == "ICON_KND_" .. species)
      entry = entries[entry]
      assert(entry.width == 16 and entry.height == 32)
    end
    assert(entry.frames == 2)
    assert(entry.image == ("mods/test/assets/party_icons/%04d.png"):format(row.dex))
    local file = assert(io.open(("assets/party_icons/%04d.png"):format(row.dex), "rb"))
    assert(file:read(8) == "\137PNG\13\10\26\10")
    file:close()
  end
  assert(count == 1025)
  local wrapper = menu.drawIcon
  ready()
  assert(menu.drawIcon == wrapper, "double wrapping")
  local palettes = {}
  local owner = {palettes = palettes}
  assert(menu.drawIcon(owner, {species = "BULBASAUR"}) == "drawn")
  assert(shader == "original-shader" and owner.palettes == palettes)
  menu.drawIcon(owner, {species = "BULBASAUR", isEgg = true})
  menu.drawIcon(owner, {species = "UNSUPPORTED"})
  fail = true
  assert(not pcall(menu.drawIcon, owner, {species = "BULBASAUR"}))
  assert(shader == "original-shader" and owner.palettes == palettes)
  assert(draws == 4)
end
print("PASS: 1,025 icon assignments in each engine; eggs, fallback, palette restoration, error cleanup")
