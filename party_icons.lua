-- Species assignments use native registries; keep native animation and held-item
-- rendering. Only our own icons bypass the cartridge's grayscale palette pass.
return function(mod, dexArt, maxDex, gen1)
  local assigned = {}
  local function assign(species, value)
    if mod.content.icons:get(species) then
      mod.content.icons:override(species, value)
    else
      mod.content.icons:register(species, value)
    end
  end
  for species, art in pairs(dexArt) do
    if art.dex <= maxDex and mod.content.pokemon:get(species) then
      local path = mod.assets:path(("assets/party_icons/%04d.png"):format(art.dex))
      if gen1 then
        assign(species, {image = path, frames = 2})
      else
        local sheet = "ICON_KND_" .. species
        mod.content.icons:register(sheet, {
          image = path, width = 16, height = 32, frames = 2,
        })
        assign(species, sheet)
      end
      assigned[species] = true
    end
  end

  local function install()
    local name = gen1 and "src.ui.PartyMenu" or "src.ui.gen2.PartyMenu"
    local ok, menu = pcall(require, name)
    if not ok or type(menu.drawIcon) ~= "function" or menu._kndPartyIcons then return end
    local original = menu.drawIcon
    menu.drawIcon = function(owner, mon, ...)
      if not mon or mon.isEgg or not assigned[mon.species] then
        return original(owner, mon, ...)
      end
      local graphics = love and love.graphics
      local shader = graphics and graphics.getShader and graphics.getShader()
      if graphics and graphics.setShader then graphics.setShader() end
      local palettes = owner.palettes
      if not gen1 then owner.palettes = nil end
      local success, result = pcall(original, owner, mon, ...)
      if not gen1 then owner.palettes = palettes end
      if graphics and graphics.setShader then graphics.setShader(shader) end
      if not success then error(result, 0) end
      return result
    end
    menu._kndPartyIcons = true
  end
  install()
  mod.events:on("game.ready", install)
end
