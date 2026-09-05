-- Pokédex AREA integration for progression-balanced wild tables, starter
-- gifts, evolution-only starter stages, and distributed static encounters.
return function(mod, encounters, extraEncounters, catalog, dexArt, gen1, placements, gameVersion)
  local areas = {}
  local normalizedVersion = tostring(gameVersion or ""):lower()
  local crystal = not gen1 and normalizedVersion:find("crystal", 1, true) ~= nil

  local function sortedKeys(t)
    local keys = {}
    for key in pairs(t or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
  end

  local function info(species)
    local row = areas[species]
    if not row then
      row = { method = "WILD ENCOUNTER", locations = {}, seen = {} }
      areas[species] = row
    end
    return row
  end

  local function canonicalMap(mapId)
    if not gen1 then
      local gen2Kanto = {
        ROUTE_10="ROUTE_10_NORTH",
        MT_MOON_1F="MOUNT_MOON",MT_MOON_B1F="MOUNT_MOON",
        MT_MOON_B2F="MOUNT_MOON",VICTORY_ROAD_1F="VICTORY_ROAD",
        VICTORY_ROAD_2F="VICTORY_ROAD",VICTORY_ROAD_3F="VICTORY_ROAD",
      }
      return gen2Kanto[mapId] or mapId
    end
    return mapId
  end

  local function fullMapLabel(mapId, region)
    local id = canonicalMap(mapId) or "UNKNOWN"
    id = id:gsub("POKEMON_", "PKMN ")
      :gsub("SILVER_CAVE", "MT SILVER")
      :gsub("MOUNT_MORTAR", "MT MORTAR")
      :gsub("MOUNT_MOON", "MT MOON")
      :gsub("MT_MOON", "MT MOON")
      :gsub("CERULEAN_CAVE", "CERULEAN CAVE")
      :gsub("SEAFOAM_ISLANDS", "SEAFOAM")
      :gsub("WHIRL_ISLAND", "WHIRL ISLANDS")
      :gsub("TIN_TOWER", "TIN TOWER")
      :gsub("VICTORY_ROAD", "VICTORY ROAD")
      :gsub("_B%d+F.*$", "")
      :gsub("_%d+F.*$", "")
      :gsub("_ROOM_%d+.*$", "")
      :gsub("_NORTH$", "")
      :gsub("_SOUTH$", "")
      :gsub("_EAST$", "")
      :gsub("_WEST$", "")
      :gsub("_", " ")
    return (region == "johto" and "J: " or "K: ") .. id
  end

  local function prettyMap(mapId, region)
    local label = fullMapLabel(mapId, region)
    if #label > 18 then label = label:sub(1, 18) end
    return label
  end

  local function addLocation(species, mapId, label, region, markerMap)
    if type(species) ~= "string" or type(mapId) ~= "string" then return end
    local row = info(species)
    local key = canonicalMap(mapId)
    if row.seen[key] then return end
    row.seen[key] = true
    local resolvedRegion = region or "kanto"
    row.locations[#row.locations + 1] = {
      map = mapId,
      nativeMap = canonicalMap(markerMap or mapId),
      label = label or prettyMap(mapId, resolvedRegion),
      uiName = label or fullMapLabel(mapId, resolvedRegion),
      region = resolvedRegion,
    }
  end

  -- Gen 2 cartridge tables supply the native wild species and the
  -- mod's 747-species completion overlay supplies the rest of the wild set.
  for _, mapId in ipairs(sortedKeys(encounters)) do
    local mapRow = encounters[mapId]
    for _, terrain in pairs(mapRow) do
      for _, slot in ipairs((type(terrain) == "table" and terrain.slots) or {}) do
        addLocation(slot.species, mapId)
      end
    end
  end
  local completionMaps = (extraEncounters and extraEncounters.maps) or {}
  local completionRegions = (extraEncounters and extraEncounters.regions) or {}
  for _, mapId in ipairs(sortedKeys(completionMaps)) do
    local mapRow = completionMaps[mapId]
    for _, pool in pairs(mapRow) do
      for _, slot in ipairs(pool) do
        addLocation(slot.species, mapId, nil, completionRegions[mapId] or "kanto")
      end
    end
  end

  local idByDex = {}
  for species, art in pairs(dexArt or {}) do
    if type(art) == "table" and type(art.dex) == "number" then
      idByDex[art.dex] = species
    end
  end

  -- A starter's base stage points to its real gift map; its two later stages say
  -- which preceding partner evolves into them instead of pretending they are
  -- wild encounters.
  for _, group in ipairs(catalog.starterGroups or {}) do
    for _, base in ipairs(group.species or {}) do
      local firstDex = dexArt[base] and dexArt[base].dex
      for offset = 0, 2 do
        local species = firstDex and idByDex[firstDex + offset]
        if species then
          local row = { locations = {}, seen = {} }
          areas[species] = row
          if offset == 0 then
            local gift = placements and placements.starters and placements.starters[base]
            local hidden = placements and placements.hiddenStarterGifts
              and placements.hiddenStarterGifts[base]
            if hidden then
              row.method = "NATIVE GIFT"
            else
              row.method = "GIFT: " .. ((gift and gift.label) or "KANTO")
            end
            if #row.method > 18 then row.method = row.method:sub(1, 18) end
          else
            local source = idByDex[firstDex + offset - 1] or base
            row.method = "EVOLVE: " .. source
            if #row.method > 18 then row.method = row.method:sub(1, 18) end
          end
          local gift = placements and placements.starters and placements.starters[base]
          if gift then
            addLocation(species, gift.map, gift.label, gift.region, gift.nativeMap)
          end
        end
      end
    end
  end

  local gen1Native = {
    ARTICUNO = { "SEAFOAM_ISLANDS_B4F", "STATIC: SEAFOAM" },
    ZAPDOS = { "POWER_PLANT", "STATIC: POWERPLANT" },
    MOLTRES = { "VICTORY_ROAD_2F", "STATIC: VICTORY RD" },
    MEWTWO = { "CERULEAN_CAVE_B1F", "STATIC: CERULEAN" },
  }
  local gen2Native = {
    RAIKOU = { nil, "ROAMING: JOHTO" },
    ENTEI = { nil, "ROAMING: JOHTO" },
    SUICUNE = { nil, "ROAMING: JOHTO" },
    LUGIA = { "WHIRL_ISLAND_LUGIA_CHAMBER", "STATIC: WHIRL IS.", "J: WHIRL ISLANDS" },
    HO_OH = { "TIN_TOWER_ROOF", "STATIC: TIN TOWER", "J: TIN TOWER" },
  }
  if crystal then
    -- Crystal replaces Suicune's roaming encounter with the cartridge-native
    -- level-40 Tin Tower battle. Raikou and Entei remain roamers.
    gen2Native.SUICUNE = {
      "TIN_TOWER_1F", "STATIC: TIN TOWER", "J: TIN TOWER"
    }
  end

  local questMethods = {
    ARTICUNO="QUEST: BIRD SURVEY",ZAPDOS="QUEST: BIRD SURVEY",
    MOLTRES="QUEST: BIRD SURVEY",REGIROCK="QUEST: REGI SEALS",
    REGICE="QUEST: REGI SEALS",REGISTEEL="QUEST: REGI SEALS",
    REGIELEKI="QUEST: REGI SEALS",REGIDRAGO="QUEST: REGI SEALS",
    REGIGIGAS="QUEST: REGI SEALS",CRESSELIA="QUEST: LUNAR DUO",
    DARKRAI="QUEST: LUNAR DUO",
  }
  for _,family in ipairs(catalog.familyQuests or {}) do
    for _,stage in ipairs(family.stages or {}) do
      for _,species in ipairs(stage) do
        questMethods[species]=family.method
      end
    end
  end

  for _, spot in ipairs(catalog.staticSpecies or {}) do
    local native = gen1 and gen1Native[spot.species] or gen2Native[spot.species]
    areas[spot.species] = { locations = {}, seen = {} }
    local row = areas[spot.species]
    if native then
      row.method = questMethods[spot.species] or native[2]
      if native[1] then
        addLocation(spot.species, native[1], native[3],
          gen1 and "kanto" or (spot.species == "LUGIA" and "johto" or "johto"))
      end
    else
      local placed = placements and placements.statics and placements.statics[spot.species]
      row.method = questMethods[spot.species]
        or ("STATIC: " .. ((placed and placed.label) or ("GEN " .. tostring(spot.generation))))
      if #row.method > 18 then row.method = row.method:sub(1, 18) end
      if placed then
        addLocation(spot.species, placed.map, placed.label, placed.region, placed.nativeMap)
      end
    end
  end

  for _,gift in ipairs(catalog.giftSpecies or {}) do
    local placed=placements and placements.gifts and placements.gifts[gift.species]
    areas[gift.species]={locations={},seen={},method="GIFT: AFTER "..gift.after}
    if #areas[gift.species].method>18 then
      areas[gift.species].method=areas[gift.species].method:sub(1,18)
    end
    if placed then
      addLocation(gift.species,placed.map,placed.label,placed.region,placed.nativeMap)
    end
  end

  local function firstLabel(row)
    local loc = row and row.locations and row.locations[1]
    return loc and loc.label or nil
  end

  -- Gen I AREA opens src.ui.TownMap. Preserve the native map and nest icons,
  -- union in this mod's Kanto markers, then add a compact acquisition footer
  -- so Kanto gifts, evolutions and statics are still readable.
  if gen1 then
    local okTown, TownMap = pcall(require, "src.ui.TownMap")
    local okFont, Font = pcall(require, "src.render.Font")
    if okTown and okFont and type(TownMap) == "table"
      and type(TownMap.new) == "function" and type(TownMap.draw) == "function" then
      TownMap.__kjAreaProvider = function(species) return areas[species] end
      if not TownMap.__kjAreaInstalled then
        TownMap.__kjAreaInstalled = true
        local originalNew = TownMap.new
        TownMap.new = function(game, opts)
          local self = originalNew(game, opts)
          local species = opts and opts.nestSpecies
          local row = species and TownMap.__kjAreaProvider(species)
          if not row then return self end
          self.kjArea = row
          local held = {}
          for _, loc in ipairs(self.nests or {}) do held[loc] = true end
          for _, where in ipairs(row.locations or {}) do
            local loc = self.byMap and self.byMap[where.nativeMap]
            if loc and not held[loc] then
              held[loc] = true
              self.nests[#self.nests + 1] = loc
            end
          end
          return self
        end

        local originalDraw = TownMap.draw
        TownMap.draw = function(self)
          originalDraw(self)
          if not (self.nestSpecies and self.kjArea) then return end
          local G = love.graphics
          G.setColor(1, 1, 1, 1)
          G.rectangle("fill", 0, 112, 160, 32)
          G.setColor(0, 0, 0, 1)
          Font.draw(self.kjArea.method or "AREA", 8, 113)
          local label = firstLabel(self.kjArea)
          if label then Font.draw(label, 8, 123) end
          local count = #(self.kjArea.locations or {})
          if count > 1 then Font.draw("+" .. tostring(count - 1) .. " MORE AREAS", 8, 133) end
          if #(self.nests or {}) == 0 then
            G.setColor(1, 1, 1, 1)
            G.rectangle("fill", 0, 0, 160, 8)
            G.setColor(0, 0, 0, 1)
            local def = self.game.data.pokemon[self.nestSpecies]
            Font.draw(((def and def.name) or self.nestSpecies) .. "'S AREA", 8, 0)
          end
          G.setColor(1, 1, 1, 1)
        end
      end
    elseif mod.log and mod.log.warn then
      mod.log:warn("Pokédex AREA integration could not patch the Gen I TownMap")
    end
  else
    -- Gen 2 AREA renderer asks Nests.find for landmark bytes. Union the
    -- catalog's maps into that answer and keep its native dynamic roamer dots.
    local okNests, Nests = pcall(require, "src.core.gen2.Nests")
    if okNests and type(Nests) == "table" and type(Nests.find) == "function" then
      Nests.__kjAreaProvider = function(species) return areas[species] end
      if not Nests.__kjAreaInstalled then
        Nests.__kjAreaInstalled = true
        local originalFind = Nests.find
        Nests.find = function(data, species, region, save)
          local out = originalFind(data, species, region, save)
          local seen = {}
          for _, landmark in ipairs(out) do seen[landmark] = true end
          local row = Nests.__kjAreaProvider(species)
          for _, where in ipairs((row and row.locations) or {}) do
            local def = data and data.gen2Maps and data.gen2Maps[where.nativeMap]
            local landmark = def and def.landmark
            local foundRegion = Nests.regionOf(landmark)
            if landmark and not seen[landmark]
              and (not region or region == foundRegion) then
              seen[landmark] = true
              out[#out + 1] = landmark
            end
          end
          table.sort(out)
          return out
        end
      end
    end

    local okDex, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if okDex and type(PokedexMenu) == "table"
      and type(PokedexMenu.drawArea) == "function" then
      PokedexMenu.__kjAreaProvider = function(species) return areas[species] end
      if not PokedexMenu.__kjAreaInstalled then
        PokedexMenu.__kjAreaInstalled = true
        local originalDrawArea = PokedexMenu.drawArea
        PokedexMenu.drawArea = function(self)
          originalDrawArea(self)
          local current = self:current()
          local row = current and PokedexMenu.__kjAreaProvider(current.species)
          if row then
            self:blank(0, 15, 20, 1)
            self:text(row.method or "AREA", 1, 15)
          end
        end
      end
    elseif mod.log and mod.log.warn then
      mod.log:warn("Pokédex AREA integration could not patch Gold's Pokédex")
    end
  end

  mod.exports.pokedexAreas = function(species)
    local row = areas[species]
    if not row then return nil end
    local copy = { method = row.method, locations = {} }
    for index, loc in ipairs(row.locations or {}) do
      copy.locations[index] = {
        map = loc.map, nativeMap = loc.nativeMap,
        label = loc.label, uiName = loc.uiName, region = loc.region,
      }
    end
    return copy
  end

  if mod.log and mod.log.info then
    local count = 0
    for _ in pairs(areas) do count = count + 1 end
    mod.log:info("Pokédex AREA catalog loaded for %d species", count)
  end
end
