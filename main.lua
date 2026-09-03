local mod = ...

-- Load this mod's own generated modules through the public scoped file API.
-- This avoids depending on Lua's package search path or engine internals.
local function ownModule(path)
  local source = assert(mod:read(path), "missing mod data: " .. path)
  local chunk, err = loadstring(source, "@" .. path)
  assert(chunk, err)
  return chunk()
end

local function cartridgeVersion()
  local value=mod.game and mod.game.version or nil
  if value==nil then
    local ok,GameVersion=pcall(require,"src.core.GameVersion")
    if ok and type(GameVersion)=="table" and type(GameVersion.get)=="function" then
      local got,current=pcall(GameVersion.get)
      if got then value=current end
    end
  end
  return tostring(value or "unknown"):lower()
end

local function isGen1()
  local version=cartridgeVersion()
  if version:find("crystal",1,true) or version:find("gold",1,true)
      or version:find("silver",1,true) or version:find("gen2",1,true) then
    return false
  end
  if version:find("yellow",1,true) or version:find("red",1,true)
      or version:find("blue",1,true) or version:find("gen1",1,true) then
    return true
  end

  -- Editors and some runtime builds omit a useful version value. Prefer native
  -- map signatures over the legacy gen2Maps field: Crystal exposes Johto maps
  -- and the single VICTORY_ROAD, while R/B/Y exposes VICTORY_ROAD_2F.
  local g=mod.game
  local nativeMaps=g and g.data and g.data.maps or nil
  local function hasMap(base)
    return (nativeMaps and nativeMaps[base]~=nil)
      or mod.content.maps:get(base)~=nil
  end
  if hasMap("NEW_BARK_TOWN") or hasMap("CHERRYGROVE_CITY")
      or hasMap("VICTORY_ROAD") then return false end
  if hasMap("VICTORY_ROAD_2F") then return true end
  if g and g.data and g.data.gen2Maps~=nil then return false end
  return true
end

local sprites = ownModule("data/sprites.lua")

local variant = ownModule("data/variant.lua")
local dexArt = ownModule("data/dex_art.lua")
local animMeta = ownModule("data/anim_meta.lua")
local shinyAnimMeta = ownModule("data/anim_shiny_meta.lua")
local encounters = ownModule("data/encounters.lua")
local gen1ExtraEncounters = ownModule("data/extra_encounters.lua")
local gen2ExtraEncounters = ownModule("data/extra_encounters_gen2.lua")
local extraEncounters = isGen1() and gen1ExtraEncounters or gen2ExtraEncounters
local nativeRelocations = ownModule("data/kanto_native_relocations.lua")
local progressionSpecials = ownModule("data/progression_specials.lua")
local evolutionStages = ownModule("data/evolutions/generated/001.lua")
local generationLimits={151,251,386,493,649,721,809,905,1025}
local function generationOf(species)
  local art=dexArt and dexArt[species]
  local dex=art and tonumber(art.dex)
  if not dex then return nil end
  for generation,limit in ipairs(generationLimits) do
    if dex<=limit then return generation end
  end
  return nil
end

-- Merge species that previously came only from the removed Johto-native
-- tables into the same Kanto completion overlay used by AREA information.
if isGen1() then
  for mapId, terrains in pairs(nativeRelocations) do
    extraEncounters.maps[mapId] = extraEncounters.maps[mapId] or {}
    for terrain, additions in pairs(terrains) do
      local pool = extraEncounters.maps[mapId][terrain]
      if not pool and terrain == "indoor" then
        pool = extraEncounters.maps[mapId].grass
      end
      if not pool then
        pool = {}
        extraEncounters.maps[mapId][terrain] = pool
      end
      for _, slot in ipairs(additions) do pool[#pool + 1] = slot end
    end
  end
end

-- Expand the roster before encounter tables are validated.
mod.exports.dexCutoff = variant.maxDex
local nationalSetup = ownModule("national_setup.lua")
if type(nationalSetup) == "function" then nationalSetup(mod) end

-- Apply the supplied PixelArt pack to every species this variant actually carries.
for id, art in pairs(dexArt) do
  if art.dex <= variant.maxDex and mod.content.pokemon:get(id) then
    mod.content.pokemon:patch(id, {
      spriteFront = mod.assets:path(art.front),
      spriteBack = mod.assets:path(art.back),
      trueColor = true,
    })
  end
end

-- Registry file fields are resolved relative to the game unless converted to
-- this mod's scoped asset path first.
local function ownAsset(path)
  if type(path) == "string" and path:sub(1, 7) == "assets/" then
    return mod.assets:path(path)
  end
  return path
end

for _, id in ipairs({"KJT_SPRITE_SCIENTIST","KJT_SPRITE_MONSTER"}) do
  local def = sprites[id]
  if def then def.image = ownAsset(def.image) end
end

-- PotatoVoxel rebuilds OptionsMenu rows when one of its dynamic settings
-- changes. Other presentation mods may wrap the same update method, so the
-- rebuild can land after the native cursor has already processed Up/Down and
-- restore the row selected at the start of the tick. Preserve the intended
-- destination by stable row id. CANCEL still wraps normally because it is the
-- explicit slot after the hook-built rows.
local optionsCursorGuardInstalled = false
local function installOptionsCursorGuard()
  if optionsCursorGuardInstalled or not isGen1() then
    return optionsCursorGuardInstalled
  end

  local okMenu, OptionsMenu = pcall(require, "src.ui.OptionsMenu")
  if not (okMenu and type(OptionsMenu) == "table"
      and type(OptionsMenu.update) == "function") then
    return false
  end
  if OptionsMenu._kantoJohtoCursorGuard then
    optionsCursorGuardInstalled = true
    return true
  end

  local originalUpdate = OptionsMenu.update
  OptionsMenu.update = function(self, dt, ...)
    local input = self.game and self.game.input
    local pressedUp = input and input:wasPressed("up")
    local pressedDown = input and input:wasPressed("down")
    local rowsBefore = self.rows or {}
    local countBefore = #rowsBefore
    local indexBefore = tonumber(self.index) or 1
    local targetIndex

    if pressedUp then
      targetIndex = indexBefore > 1 and indexBefore - 1 or countBefore + 1
    elseif pressedDown then
      targetIndex = indexBefore < countBefore + 1 and indexBefore + 1 or 1
    end

    local targetIsCancel = targetIndex == countBefore + 1
    local targetRow = targetIndex and rowsBefore[targetIndex]
    local targetId = type(targetRow) == "table" and targetRow.id or nil
    local result = originalUpdate(self, dt, ...)

    if targetIndex then
      local rowsAfter = self.rows or {}
      local countAfter = #rowsAfter
      local resolved
      if targetIsCancel then
        resolved = countAfter + 1
      elseif targetId then
        for i, row in ipairs(rowsAfter) do
          if type(row) == "table" and row.id == targetId then
            resolved = i
            break
          end
        end
      end
      resolved = resolved or math.max(1, math.min(targetIndex, countAfter + 1))

      local selected = rowsAfter[self.index or 1]
      local selectedId = type(selected) == "table" and selected.id or nil
      local destinationLost = (targetIsCancel and self.index ~= countAfter + 1)
        or (not targetIsCancel and targetId and selectedId ~= targetId)
        or (not targetIsCancel and not targetId and self.index ~= resolved)
      if destinationLost then
        self.index = resolved
        local okRows, OptionRows = pcall(require, "src.ui.OptionRows")
        if okRows and OptionRows and type(OptionRows.clampScroll) == "function" then
          self.scroll = OptionRows.clampScroll(
            self.index, self.scroll or 0, countAfter, countAfter + 1)
        end
      end
    end
    return result
  end

  OptionsMenu._kantoJohtoCursorGuard = true
  optionsCursorGuardInstalled = true
  mod.log:info("Options cursor rebuild guard installed")
  return true
end

mod.events:on("game.ready", function()
  installOptionsCursorGuard()
end)


-- Species animation support is independent of the removed map import.
local installAnimatedSprites = ownModule("animated_sprites.lua")
if type(installAnimatedSprites) == "function" then
  installAnimatedSprites(mod, dexArt, animMeta, shinyAnimMeta, isGen1())
end

-- Starter gifts and non-native legendary/mythical statics are distributed
-- across collision-checked native Kanto maps on both engines.
local installProgressionAcquisition = ownModule("progression_acquisition.lua")
if type(installProgressionAcquisition) == "function" then
  installProgressionAcquisition(mod, progressionSpecials, sprites, isGen1(),
    cartridgeVersion())
end

-- Rebuild every cartridge trainer party once per load. Each party slot rolls
-- generations 1-9 independently, then prefers the same primary type and
-- evolution stage while retaining its original level and any extra fields.
local installTrainerGenerationMix = ownModule("trainer_generation_mix.lua")
if type(installTrainerGenerationMix) == "table" then
  mod.exports.trainerGenerationMix=installTrainerGenerationMix(
    mod,dexArt,evolutionStages,progressionSpecials)
end

-- Keep the Pokédex AREA section synchronized with the authoritative encounter
-- overlay and with non-wild acquisition methods introduced above.
local installPokedexAreas = ownModule("pokedex_areas.lua")
if type(installPokedexAreas) == "function" then
  installPokedexAreas(mod, encounters, extraEncounters, progressionSpecials,
    dexArt, isGen1(), mod.exports.progressionPlacements, cartridgeVersion())
end



-- ---------------------------------------------------------------------------
-- GameShark compatibility
-- ---------------------------------------------------------------------------
-- The completion encounter wrapper is intentionally authoritative and
-- can return an encounter without calling `next`. That used to bypass
-- GameShark's NO BATTLES wrapper. Read GameShark's public export first so the
-- cheat remains authoritative for completion encounters.
local gameSharkHandle
local function rowsHaveNoBattles(exports)
  if type(exports) ~= "table" or type(exports.list) ~= "function" then return false end
  local ok, rows = pcall(exports.list, mod.game)
  if not ok or type(rows) ~= "table" then return false end
  for _, row in ipairs(rows) do
    if row.effect == "no_encounters" and row.enabled == true then return true end
  end
  return false
end

local function gameSharkNoBattles()
  -- v0.8+ integrates GameShark/CHEATS into this mod, so its public exports live
  -- directly on `mod.exports`. Check those first. This must happen before our
  -- completion encounter roll can return without calling next.
  if rowsHaveNoBattles(mod.exports) then return true end

  -- Keep the legacy external lookup as a compatibility fallback for older
  -- layouts/dev builds where GameShark is still loaded as its own mod.
  local handle = gameSharkHandle
  if not handle then
    local ok, found = pcall(function() return mod:find("GameShark") end)
    if ok and type(found) == "table" then
      gameSharkHandle = found
      handle = found
    end
  end
  return rowsHaveNoBattles(handle and handle.exports)
end

-- Generation-balanced Kanto encounter runtime. The cartridge still decides
-- whether an encounter occurs; after a successful roll, native and added
-- species share one evenly generation-weighted species table.
local completionPoolCache={}
local function completionRow(mapId, terrain)
  local cacheKey=tostring(mapId).."|"..tostring(terrain)
  local cached=completionPoolCache[cacheKey]
  if cached~=nil then return cached or nil end
  local aliases = {
    ROUTE_10_NORTH={"ROUTE_10"}, ROUTE_10_SOUTH={"ROUTE_10"},
    MOUNT_MOON={"MT_MOON_1F","MT_MOON_B1F","MT_MOON_B2F"},
    VICTORY_ROAD={"VICTORY_ROAD_1F","VICTORY_ROAD_2F","VICTORY_ROAD_3F"},
  }
  local direct=extraEncounters and extraEncounters.maps
    and extraEncounters.maps[mapId]
  local ids=direct and {mapId} or (aliases[mapId] or {mapId})
  local combined={}
  for _,id in ipairs(ids) do
    local row=extraEncounters and extraEncounters.maps
      and extraEncounters.maps[id]
    if row then
      local pool=row[terrain]
      if not pool and terrain=="grass" then pool=row.indoor end
      if not pool and terrain=="indoor" then pool=row.grass end
      for _,slot in ipairs(pool or {}) do combined[#combined+1]=slot end
    end
  end
  completionPoolCache[cacheKey]=#combined>0 and combined or false
  return completionPoolCache[cacheKey] or nil
end

local nativeEncounterPool=ownModule("native_encounter_pool.lua")
local function groupedByGeneration(pool,encDef,rolled,ctx)
  local groups,seen={},{ }
  for generation=1,9 do groups[generation]={};seen[generation]={} end
  local function add(slot)
    if type(slot)~="table" or type(slot.species)~="string" then return false end
    local generation=generationOf(slot.species)
    if generation then
      -- Choose species uniformly, while retaining its available level rows as
      -- variants. Duplicate slots can never increase a species' spawn share.
      local entry=seen[generation][slot.species]
      if not entry then
        entry={species=slot.species,variants={}}
        seen[generation][slot.species]=entry
        groups[generation][#groups[generation]+1]=entry
      end
      entry.variants[#entry.variants+1]=slot
      return true
    end
    return false
  end
  for _,slot in ipairs(pool or {}) do add(slot) end

  -- Gen II passes all maps, terrains and time periods into this hook. Only
  -- collect the active list; traversing encDef directly leaks distant mons.
  local visited,nativeRows={},0
  local function collect(value,depth)
    if type(value)~="table" or depth>7 or visited[value] then return end
    visited[value]=true
    if type(value.species)=="string" then
      if add(value) then nativeRows=nativeRows+1 end
      return
    end
    for _,child in pairs(value) do collect(child,depth+1) end
  end
  collect(nativeEncounterPool(encDef,ctx,isGen1()),0)
  if nativeRows==0 then add(rolled) end
  return groups
end

local function applyGenerationBalance(base,mapId,terrain,encDef,rng,ctx)
  if not base then return nil end
  local pool=completionRow(mapId,terrain)
  if not (pool and #pool>0) then return base end
  local groups=groupedByGeneration(pool,encDef,base,ctx)
  local represented={}
  for generation=1,9 do
    if #groups[generation]>0 then represented[#represented+1]=generation end
  end
  if #represented==0 then return base end
  local generation=represented[rng(1,#represented)]
  local choices=groups[generation]
  local species=choices[rng(1,#choices)]
  local variants=species and species.variants or {}
  local variant=variants[rng(1,#variants)]
  return {species=species.species,level=(variant and variant.level) or base.level}
end

mod.hooks:wrap("encounter.roll",function(next,encDef,ctx)
  if gameSharkNoBattles() then return nil end
  local rolled=next(encDef,ctx)
  if not rolled or not (ctx and ctx.mapId) then return rolled end
  if ctx.kind and ctx.kind~="wild" then return rolled end
  if type(ctx.mapId)=="string" and ctx.mapId:find("RUINS_OF_ALPH",1,true) then
    return rolled
  end
  return applyGenerationBalance(rolled,ctx.mapId,ctx.terrain,encDef,
    ctx.rng or math.random,ctx)
end,1000)

-- -------------------------------------------------------------------------
-- Integrated QoL / Cheats suite
-- The standalone projects are loaded inside this mod so they share one
-- options namespace and compose with the expanded Dex.
-- Duplicate behaviors are intentionally disabled in their secondary source.
local function initIntegrated(path)
  local entry = ownModule(path)
  assert(type(entry) == "function", "integrated entry did not return initializer: " .. path)
  entry(mod)
end

initIntegrated("integrated_qol_toggles.lua")
initIntegrated("qol_integrated_main.lua")
if isGen1() then
  initIntegrated("integrated_swuff_qol.lua")
end
initIntegrated("integrated_cheats.lua")
initIntegrated("switch_same_mon_cancel.lua")
initIntegrated("capture_ball_continuity.lua")

-- Add the unique features from the other QoL packs to the single OPTIONS ->
-- QOL card grid.  The later-gen pack keeps its richer nested configuration
-- screen, but it is reachable only from this QOL submenu.
do
  local baseRows = mod.exports.toggleRows
  if type(baseRows) == "function" then
    local SWUFF_ROWS = {
      { key="faster_battles",      label="BETTER BATTLES",     help="Faster HP bars and battle presentation." },
      { key="color_attacks",       label="COLOR ATTACKS",      help="Move animations inherit their move type color." },
      { key="hidden_stats",        label="DVs / STAT EXP",     help="Adds a summary page showing DVs and stat EXP." },
      { key="expanded_move_info",  label="MORE MOVE INFO",     help="START on the moves summary page shows power and move details." },
      { key="quick_party_reorder", label="QUICK REORDER",      help="Press SELECT in the party menu to quickly reorder Pokemon." },
      { key="free_fly_map",        label="CURSOR FLY MAP",     help="Use a crosshair-style Fly map instead of the vanilla list." },
      { key="extra_fly_spots",     label="NEW FLY SPOTS",      help="Adds Mt. Moon and Rock Tunnel Pokemon Center Fly destinations." },
      { key="relearn_button",      label="RELEARN ANYWHERE",   help="Relearn previously known moves from the Pokemon menu." },
      { key="bag_30",              label="30-ITEM BAG",        help="Raises the Gen 1 bag capacity from 20 to 30. Reload after changing." },
      { key="boxes_14",            label="16 PC BOXES",        help="Raises Gen 1 PC storage to 16 boxes. Reload after changing." },
    }

    local function bucketFor(container)
      if not container then return nil end
      container.modOptions = container.modOptions or {}
      container.modOptions[mod.id] = container.modOptions[mod.id] or {}
      return container.modOptions[mod.id]
    end

    local function setIntegratedOption(game, key, value)
      local bucket = game and game.save and bucketFor(game.save.options)
      if bucket then bucket[key] = value end
      local liveBucket = game and bucketFor(game.mods)
      if liveBucket then liveBucket[key] = value end
      if game and game.writeOptions then
        game:writeOptions()
      elseif game and game.persistOptions then
        game:persistOptions()
      end
    end

    mod.exports.toggleRows = function(getFn, setFn, gen2)
      local rows = baseRows(getFn, setFn, gen2)
      rows[#rows + 1] = {
        id = "later_gen_qol",
        label = "LATER GEN QOL",
        cardLines = { "LATER GEN", "QOL" },
        cardTickers = {},
        help = "Caught indicator and configurable easy interactions.",
        value = function() return "OPEN" end,
        step = function(game)
          mod.ui.push(game or mod.game, "QualityOfLife")
          return true
        end,
      }

      if isGen1() then
        for _, spec in ipairs(SWUFF_ROWS) do
          rows[#rows + 1] = {
            id = "swuff_" .. spec.key,
            label = spec.label,
            cardLines = mod.exports.cardLabelLines(spec.label),
            cardTickers = {},
            help = spec.help,
            value = function()
              return mod.options:get(spec.key) == "on" and "ON" or "OFF"
            end,
            step = function(game)
              local newValue = mod.options:get(spec.key) == "on" and "off" or "on"
              setIntegratedOption(game or mod.game, spec.key, newValue)
              return true
            end,
          }
        end
      end
      return rows
    end
  end
end
