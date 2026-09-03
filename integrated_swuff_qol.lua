return function(mod)
  local HISTORY_FIELD = "party_nickname_relearn"
  local HISTORY_VERSION = 1
  local warnedDeltaApi = false
  local liveGame = nil

  local function toggleOption(key, label, defaultOn)
    return {
      key = key,
      type = "choice",
      label = label,
      choices = defaultOn
        and { { "ON (DEFAULT)", "on" }, { "OFF", "off" } }
        or  { { "OFF (DEFAULT)", "off" }, { "ON", "on" } },
      default = defaultOn and "on" or "off",
    }
  end

  mod.options:define({
    toggleOption("faster_battles", "BETTER BATTLES", true),
    toggleOption("color_attacks", "COLOR ATTACKS", true),
    toggleOption("hidden_stats", "SHOW DVs/STAT EXP", true),
    toggleOption("expanded_move_info", "MORE MOVE INFO", true), 
    toggleOption("quick_party_reorder", "SELECT TO REORDER", true),
    toggleOption("free_fly_map", "CURSOR FLY MAP", true),
    toggleOption("extra_fly_spots", "NEW FLY SPOTS", false),
    toggleOption("relearn_button", "RELEARN ANYWHERE", false),
    toggleOption("bag_30", "30-ITEM BAG", false),
    toggleOption("boxes_14", "16 PC BOXES", true),
  })

  local DEDUPED = {
    battle_xp_bar = true,       -- canonical: QoL Toggles EXP BAR
    summary_party_cycle = true, -- canonical: QoL Toggles PARTY SCROLL
    field_hm_shortcuts = true,  -- canonical: Quality/EASY INTERACTIONS
    repel_reuse = true,         -- canonical: Quality/REPEL PROMPT
    forgettable_hms = true,     -- canonical: QoL Toggles FORGETTABLE HMs
    nickname_button = true,     -- canonical: QoL Toggles RENAME
  }
  local function featureOn(key)
    if DEDUPED[key] then return false end
    return mod.options:get(key) == "on"
  end

  if featureOn("bag_30") then
    local currentBagSize = tonumber(mod.content.constants:get("bagSize")) or 20
    if currentBagSize < 30 then mod.content.constants:patch("bagSize", 30) end
  end

  do
    local Boxes = require("src.pokemon.Boxes")
    Boxes.__menuQoLBaseCount = Boxes.__menuQoLBaseCount or Boxes.COUNT or 12
    Boxes.__menuQoLOriginalEnsure = Boxes.__menuQoLOriginalEnsure or Boxes.ensure

    if not Boxes.__menuQoLEnsureWrapped then
      Boxes.__menuQoLEnsureWrapped = true
      Boxes.ensure = function(save)
        local boxes = Boxes.__menuQoLOriginalEnsure(save)
        for i = 1, Boxes.COUNT do
          if boxes[i] == nil then boxes[i] = {} end
        end
        return boxes
      end
    end

    local BOX_TARGET = 16
    if featureOn("boxes_14") then
      local before = tonumber(Boxes.COUNT) or 12
      if before < BOX_TARGET then
        Boxes.COUNT = BOX_TARGET
        Boxes.__menuQoLSetCount = true
        Boxes.__menuQoLAppliedCount = BOX_TARGET
      end
    elseif Boxes.__menuQoLSetCount
       and (Boxes.COUNT == 14 or Boxes.COUNT == BOX_TARGET) then
      Boxes.COUNT = Boxes.__menuQoLBaseCount
      Boxes.__menuQoLSetCount = false
      Boxes.__menuQoLAppliedCount = nil
    end
  end

  local function partyIndex(game, mon)
    local party = game and game.save and game.save.party or {}
    for i, candidate in ipairs(party) do
      if candidate == mon then return i, party end
    end
    return nil, party
  end

  local function adjacentPartyMon(game, mon, delta)
    local index, party = partyIndex(game, mon)
    if not index or #party < 2 then return nil, nil end
    local nextIndex = ((index - 1 + delta) % #party) + 1
    return party[nextIndex], nextIndex
  end

  local function cycleOwnedMon(owner, delta)
    if not (owner and owner.game and owner.mon) then return false end
    local nextMon, nextIndex = adjacentPartyMon(owner.game, owner.mon, delta)
    if not nextMon then return false end
    owner.mon = nextMon
    if type(owner.refreshMon) == "function" then owner:refreshMon(nextMon) end
    owner.game.partyMenuSavedIndex = nextIndex
    return true
  end

  local NativeSummaryMenu = require("src.ui.SummaryMenu")
  local Stats = require("src.pokemon.Stats")
  local HiddenStatsScreen = {}
  HiddenStatsScreen.__index = HiddenStatsScreen
  HiddenStatsScreen.isOpaque = true

  function HiddenStatsScreen:sgbPalettes(game)
    local P = require("src.render.PaletteFX")
    local mon = self.mon
    if not mon then return { P.whole(P.GRAYS) } end
    local zones = { P.whole(P.GRAYS) }
    local monPal = P.monPal(game.data, mon.species)
    if monPal then zones[#zones + 1] = P.zone(monPal, 1, 0, 7, 6) end
    return zones
  end

  local function hpDV(dvs)
    dvs = dvs or {}
    if dvs.hp ~= nil then return math.max(0, math.min(15, tonumber(dvs.hp) or 0)) end
    local attack = tonumber(dvs.attack) or 0
    local defense = tonumber(dvs.defense) or 0
    local speed = tonumber(dvs.speed) or 0
    local special = tonumber(dvs.special) or 0
    return (attack % 2) * 8 + (defense % 2) * 4
         + (speed % 2) * 2 + (special % 2)
  end

  local function hiddenValues(mon)
    local dvs = (mon and mon.dvs) or {}
    local statExp = (mon and mon.statExp) or {}
    return {
      dv = {
        hp = hpDV(dvs),
        attack = tonumber(dvs.attack) or 0,
        defense = tonumber(dvs.defense) or 0,
        speed = tonumber(dvs.speed) or 0,
        special = tonumber(dvs.special) or 0,
      },
      exp = {
        hp = tonumber(statExp.hp) or 0,
        attack = tonumber(statExp.attack) or 0,
        defense = tonumber(statExp.defense) or 0,
        speed = tonumber(statExp.speed) or 0,
        special = tonumber(statExp.special) or 0,
      },
    }
  end

  local function refreshSummarySprite(owner, mon)
    owner.sprite = nil
    owner.spriteTrueColor = false
    if not (owner and owner.game and mon) then return end
    local Sprites = require("src.pokemon.Sprites")
    local path, trueColor = Sprites.path(owner.game.data, mon.species, "front",
      { mon = mon, kind = "summary" })
    if path then
      local ok, img = pcall(love.graphics.newImage, path)
      owner.sprite = ok and img or nil
      owner.spriteTrueColor = owner.sprite and trueColor or false
    end
  end

  local function newHiddenStatsScreen(game, mon)
    Stats.ensure(game.data.pokemon[mon.species], mon)
    local self = setmetatable({
      game = game,
      mon = mon,
    }, HiddenStatsScreen)
    refreshSummarySprite(self, mon)
    return self
  end

  function HiddenStatsScreen:refreshMon(mon)
    refreshSummarySprite(self, mon or self.mon)
  end

  local function hiddenToNativeSummary(self, page)
    local game, mon = self and self.game, self and self.mon
    if not (game and mon and game.stack) then return false end

    if game.stack:top() == self then game.stack:pop() end
    local underneath = game.stack:top()
    if underneath and underneath.screenId == "SummaryMenu" then
      game.stack:pop()
    end

    mod.ui.push(game, "SummaryMenu", mon)
    local replacement = game.stack:top()
    if replacement and replacement.screenId == "SummaryMenu" then
      replacement.page = page == 2 and 2 or 1
    end
    local index = partyIndex(game, mon)
    if index then game.partyMenuSavedIndex = index end
    return true
  end

  function HiddenStatsScreen:update(dt)
    local input = self.game and self.game.input
    if not input then return end

    if featureOn("summary_party_cycle") then
      if input:wasPressed("up") then
        cycleOwnedMon(self, -1)
        return
      elseif input:wasPressed("down") then
        cycleOwnedMon(self, 1)
        return
      elseif input:wasPressed("left") then
        hiddenToNativeSummary(self, 1)
        return
      elseif input:wasPressed("right") then
        hiddenToNativeSummary(self, 2)
        return
      end
    end

    if input:wasPressed("a") or input:wasPressed("b") then
      hiddenToNativeSummary(self, 2)
    end
  end

  local function drawLineBox(tx, ty, b, c)
    local HudTiles = require("src.render.HudTiles")
    for i = 0, b - 1 do HudTiles.statusTile(0x78, tx * 8, (ty + i) * 8) end
    HudTiles.statusTile(0x77, tx * 8, (ty + b) * 8)
    for i = 1, c do HudTiles.statusTile(0x76, (tx - i) * 8, (ty + b) * 8) end
    HudTiles.statusTile(0x6F, (tx - c - 1) * 8, (ty + b) * 8)
  end

  local function printLevel(tx, ty, level)
    local HudTiles = require("src.render.HudTiles")
    local x = tx * 8
    if level < 100 then
      HudTiles.statusTile(0x6E, x, ty * 8)
      x = x + 8
    end
    mod.ui.Font.draw(tostring(level), x, ty * 8)
  end

  function HiddenStatsScreen:draw()
    local game = self.game
    local mon = self.mon
    if not (game and mon) then return end

    local Font = mod.ui.Font
    local data = game.data
    local def = data.pokemon[mon.species]
    local HudTiles = require("src.render.HudTiles")
    local values = hiddenValues(mon)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)

    if self.sprite then
      local pw, ph = self.sprite:getDimensions()
      local py = math.max(0, 56 - ph)
      love.graphics.draw(self.sprite, 8 + pw, py, 0, -1, 1)
      if self.spriteTrueColor then
        require("src.render.PaletteFX").markTrueColor(8, py, pw, ph)
      end
    end

    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(mon.nickname or def.name, 72, 8)
    HudTiles.statusTile(0x74, 8, 56)
    Font.drawCode(0xF2, 16, 56)
    Font.draw(("%03d"):format(def.dex or 0), 24, 56)

    printLevel(14, 2, mon.level)
    drawLineBox(19, 1, 6, 10)

    HudTiles.drawHPBar(data, 11, 3, mon, 1, true)
    Font.draw("HP", 80, 32)
    Font.draw(("DV %2d"):format(values.dv.hp), 80, 40)
    Font.draw(("EXP %05d"):format(values.exp.hp), 80, 48)

    Font.drawBox(0, 8, 20, 10)
    local stats = {
      { "ATTACK", "attack" }, { "DEFENSE", "defense" },
      { "SPEED", "speed" }, { "SPECIAL", "special" },
    }
    for i, row in ipairs(stats) do
      local y = 72 + (i - 1) * 16
      Font.draw(row[1], 8, y)
      Font.draw(("DV %2d"):format(values.dv[row[2]]), 48, y + 8)
    end

    local expRows = {
      values.exp.attack,
      values.exp.defense,
      values.exp.speed,
      values.exp.special,
    }
    for i, value in ipairs(expRows) do
      local y = 72 + (i - 1) * 16
      Font.draw("EXP", 80, y)
      Font.draw(("%05d"):format(math.max(0, tonumber(value) or 0)), 104, y)
    end

    love.graphics.setColor(1, 1, 1, 1)
  end

  mod.content.screens:register("MenuQoLHiddenStats", {
    new = newHiddenStatsScreen,
  })
  local MoveDetailsScreen = {}
  MoveDetailsScreen.__index = MoveDetailsScreen
  MoveDetailsScreen.isOpaque = true

  local SPECIAL_TYPES = {
    FIRE = true, WATER = true, GRASS = true, ELECTRIC = true, ICE = true,
    PSYCHIC = true, PSYCHIC_TYPE = true, DRAGON = true,
  }

  local function displayType(typeId)
    if not typeId then return "--" end
    return tostring(typeId):gsub("_TYPE$", "")
  end

  local function displayCategory(mdef)
    if not mdef then return "--" end
    if mdef.category then return tostring(mdef.category):upper() end
    if (tonumber(mdef.power) or 0) <= 0
        and not mdef.fixedDamage and mdef.effect ~= "OHKO_EFFECT" then
      return "STATUS"
    end
    return SPECIAL_TYPES[mdef.type] and "SPECIAL" or "PHYSICAL"
  end

  local function displayPower(mdef)
    if not mdef then return "--" end
    if mdef.effect == "OHKO_EFFECT" then return "OHKO" end
    if mdef.fixedDamage ~= nil then return "FIXED" end
    local power = tonumber(mdef.power) or 0
    return power > 0 and tostring(power) or "--"
  end

  local function displayAccuracy(mdef)
    local accuracy = mdef and tonumber(mdef.accuracy) or 0
    return accuracy > 0 and tostring(accuracy) or "--"
  end

  local function selectedMove(screen)
    local moves = screen.mon and screen.mon.moves or {}
    if #moves == 0 then return nil, nil end
    screen.index = math.max(1, math.min(screen.index or 1, #moves))
    local inst = moves[screen.index]
    local def = inst and screen.game.data.moves and screen.game.data.moves[inst.id]
    return inst, def
  end

  local function newMoveDetailsScreen(game, mon)
    return setmetatable({
      game = game,
      mon = mon,
      index = 1,
      openGuard = true,
    }, MoveDetailsScreen)
  end

  function MoveDetailsScreen:update(dt)
    local input = self.game and self.game.input
    if not input then return end

    if self.openGuard then
      if input:isDown("start") or input:isDown("select") then return end
      self.openGuard = false
    end

    local moves = self.mon and self.mon.moves or {}
    if featureOn("summary_party_cycle") and input:wasPressed("left") then
      if cycleOwnedMon(self, -1) then self.index = 1 end
    elseif featureOn("summary_party_cycle") and input:wasPressed("right") then
      if cycleOwnedMon(self, 1) then self.index = 1 end
    elseif input:wasPressed("up") and #moves > 0 then
      self.index = self.index > 1 and self.index - 1 or #moves
    elseif input:wasPressed("down") and #moves > 0 then
      self.index = self.index < #moves and self.index + 1 or 1
    elseif input:wasPressed("a") or input:wasPressed("b")
        or input:wasPressed("start") or input:wasPressed("select") then
      self.game.stack:pop()
    end
  end

  function MoveDetailsScreen:draw()
    local game, mon = self.game, self.mon
    if not (game and mon) then return end
    local Font = mod.ui.Font
    local Theme = mod.ui.Theme
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(0, 0, 0, 1)

    Font.draw(mon.nickname or (def and def.name) or tostring(mon.species or "POKEMON"), 8, 8)
    Font.draw(("Lv%d"):format(tonumber(mon.level) or 1), 120, 8)
    Font.draw("MOVE INFO", 8, 24)
    Font.draw("B BACK", 104, 24)
    Font.drawBox(0, 4, 20, 9)

    local moves = mon.moves or {}
    for i = 1, 4 do
      local y = 40 + (i - 1) * 16
      local inst = moves[i]
      local mdef = inst and game.data.moves and game.data.moves[inst.id]
      if i == (self.index or 1) and inst then
        Font.drawCode(Theme.cursor, 0, y)
      end
      Font.draw((mdef and mdef.name) or (inst and tostring(inst.id)) or "-", 16, y)
    end

    local inst, mdef = selectedMove(self)
    if inst and mdef then
      local basePP = tonumber(mdef.pp) or 0
      local maxPP = basePP + (tonumber(inst.ppUps) or 0) * math.floor(basePP / 5)
      Font.draw("TYPE " .. displayType(mdef.type), 8, 112)
      Font.draw("POW " .. displayPower(mdef), 8, 120)
      Font.draw("ACC " .. displayAccuracy(mdef), 88, 120)
      Font.draw(("PP %2d/%2d"):format(tonumber(inst.pp) or 0, maxPP), 8, 128)
      Font.draw(displayCategory(mdef), 88, 128)
    else
      Font.draw("NO MOVES", 8, 120)
    end

    love.graphics.setColor(1, 1, 1, 1)
  end

  mod.content.screens:register("MenuQoLMoveDetails", {
    new = newMoveDetailsScreen,
  })

  local BuiltinTownMap = require("src.ui.TownMap")
  local FlyMap = require("src.world.Map")
  local FlySound = require("src.core.Sound")

  local FlyCrosshair = {}
  FlyCrosshair.__index = FlyCrosshair
  FlyCrosshair.isOpaque = true

  local FLY_GRID_MIN = 0
  local FLY_GRID_MAX = 15
  local FLY_HOLD_DELAY = 0.32
  local FLY_REPEAT_INTERVAL = 0.12

  local EXTRA_FLY = {
    ROUTE_4 = {
      name = "MT. MOON",
      locationIds = { "MT_MOON_1F", "MT_MOON_B1F", "ROUTE_4" },
      xOffset = 0,
    },
    ROUTE_10 = {
      name = "ROCK TUNNEL",
      locationIds = { "ROCK_TUNNEL_1F", "ROCK_TUNNEL_B1F", "ROUTE_10" },
    },
  }

  local extraFlyEnabled, syncMtMoonFlyLanding, syncRockTunnelFlyLanding
  do
    local ORIGINAL_KEY = "__menuQoLOriginalIsFlyTown"
    local DISPATCH_KEY = "__menuQoLExtraFlyDispatch"
    if not FlyMap[ORIGINAL_KEY] then
      FlyMap[ORIGINAL_KEY] = FlyMap.isFlyTown
      FlyMap.isFlyTown = function(def)
        local handler = FlyMap[DISPATCH_KEY]
        if type(handler) == "function" then
          local answer = handler(def)
          if answer ~= nil then return answer end
        end
        return FlyMap[ORIGINAL_KEY](def)
      end
    end
    FlyMap[DISPATCH_KEY] = function(def)
      if not featureOn("extra_fly_spots") then return nil end
      local id = def and def.id
      if id == "ROUTE_10" then
        syncRockTunnelFlyLanding(liveGame)
        return true
      end
      if id == "ROUTE_4" then
        syncMtMoonFlyLanding(liveGame)
        return true
      end
      return nil
    end
  end

  local function townMapTable(game)
    local tm = game and game.data and game.data.field and game.data.field.townMap
    if type(tm) == "table" and type(tm.locations) == "table" then
      return tm.locations
    end
    return type(tm) == "table" and tm or {}
  end

  local function flyEntryCoords(entry)
    if type(entry) ~= "table" then return nil, nil end
    local c = entry.coords or entry
    return tonumber(c.x or c.col), tonumber(c.y or c.row)
  end

  local function flyEntryName(entry, mapId)
    local name = type(entry) == "table" and (entry.name or entry.label) or nil
    return name or tostring(mapId or "FLY"):gsub("_", " ")
  end

  local function clampFlyGrid(v)
    return math.max(FLY_GRID_MIN, math.min(FLY_GRID_MAX, tonumber(v) or 0))
  end

  extraFlyEnabled = function()
    return mod.options:get("extra_fly_spots") == "on"
  end

  local function extraFlyMarkerCoords(game, mapId)
    local extra = EXTRA_FLY[mapId]
    if not (extra and extraFlyEnabled()) then return nil, nil end
    local entries = townMapTable(game)
    for _, locId in ipairs(extra.locationIds or {}) do
      local x, y = flyEntryCoords(entries[locId])
      if x and y then
        return clampFlyGrid(x + (extra.xOffset or 0)),
               clampFlyGrid(y + (extra.yOffset or 0))
      end
    end
    return nil, nil
  end

  local function syncFlyLandingFromDoor(game, routeId, centerId)
    if not (extraFlyEnabled() and game and game.data) then return end
    local maps = game.data.maps or {}
    local field = game.data.field or {}
    local flyWarps = field.flyWarps
    local route = maps[routeId]
    if type(flyWarps) ~= "table" or type(route) ~= "table" then return end

    for _, warp in ipairs(route.warps or {}) do
      if warp.destMap == centerId then
        local x, y = tonumber(warp.x), tonumber(warp.y)
        if x and y then
          local spot = flyWarps[routeId]
          if type(spot) ~= "table" then
            spot = {}
            flyWarps[routeId] = spot
          end
          spot.x, spot.y = x, y + 1
        end
        return
      end
    end
  end

  syncMtMoonFlyLanding = function(game)
    syncFlyLandingFromDoor(game, "ROUTE_4", "MT_MOON_POKECENTER")
  end

  syncRockTunnelFlyLanding = function(game)
    syncFlyLandingFromDoor(game, "ROUTE_10", "ROCK_TUNNEL_POKECENTER")
  end

  local function isRegisteredFlyDestination(mapId, def)
    if not def then return false end
    if FlyMap.isFlyTown(def) then return true end
    if EXTRA_FLY[mapId] then return extraFlyEnabled() end
    return FlyMap.isOutdoor(def) or def.tileset == "PLATEAU"
  end

  local function buildFlyTargets(game)
    local field = game.data.field or {}
    local entries = townMapTable(game)
    local flyWarps = field.flyWarps or {}
    local visited = game.save.visited or {}
    local targets, ordered, seenMap = {}, {}, {}

    local function coordsFor(mapId)
      local x, y = extraFlyMarkerCoords(game, mapId)
      if x and y then return x, y end
      x, y = flyEntryCoords(entries[mapId])
      if x and y then return clampFlyGrid(x), clampFlyGrid(y) end
      return nil, nil
    end

    for _, mapId in ipairs(field.flyOrder or {}) do
      if not seenMap[mapId] then
        seenMap[mapId] = true
        local def = game.data.maps and game.data.maps[mapId]
        local x, y = coordsFor(mapId)
        if visited[mapId] and flyWarps[mapId] and x and y
            and isRegisteredFlyDestination(mapId, def) then
          local extra = EXTRA_FLY[mapId]
          local target = {
            mapId = mapId,
            x = x,
            y = y,
            name = (extra and extraFlyEnabled() and extra.name)
                or flyEntryName(entries[mapId], mapId),
          }
          local key = x .. ":" .. y
          if not targets[key] then targets[key] = target end
          ordered[#ordered + 1] = target
        end
      end
    end
    return targets, ordered
  end

  local function initialFlyCursor(game, base, targets, ordered)
    local mapId = game.overworld and game.overworld.map and game.overworld.map.id
    local entries = townMapTable(game)
    local x, y = flyEntryCoords(entries[mapId])
    if not (x and y) and base and base.playerLoc then
      x, y = base.playerLoc.x, base.playerLoc.y
    end
    if x and y then return clampFlyGrid(x), clampFlyGrid(y) end

    local loc = base and base.byMap and mapId and base.byMap[mapId]
    if loc and loc.x and loc.y then
      return clampFlyGrid(loc.x), clampFlyGrid(loc.y)
    end
    if ordered[1] then return ordered[1].x, ordered[1].y end
    return 0, 0
  end

  local function newFlyCrosshair(game, opts)
    syncMtMoonFlyLanding(game)
    syncRockTunnelFlyLanding(game)
    local base = BuiltinTownMap.new(game, {})
    local targets, ordered = buildFlyTargets(game)
    local x, y = initialFlyCursor(game, base, targets, ordered)
    return setmetatable({
      game = game,
      base = base,
      onFly = opts and opts.onFly,
      targets = targets,
      ordered = ordered,
      x = x,
      y = y,
      blink = 0,
      repeatDX = 0,
      repeatDY = 0,
      repeatElapsed = 0,
      repeatNext = FLY_HOLD_DELAY,
    }, FlyCrosshair)
  end

  function FlyCrosshair:sgbPalettes(game)
    if self.base and type(self.base.sgbPalettes) == "function" then
      return self.base:sgbPalettes(game or self.game)
    end
  end

  function FlyCrosshair:target()
    return self.targets[self.x .. ":" .. self.y]
  end

  function FlyCrosshair:move(dx, dy)
    local nx = clampFlyGrid(self.x + dx)
    local ny = clampFlyGrid(self.y + dy)
    if nx == self.x and ny == self.y then return false end
    self.x, self.y = nx, ny
    FlySound.play(self.game.data, "Tink")
    return true
  end

  local function flyHeldVector(input)
    local dx = (input:isDown("right") and 1 or 0)
             - (input:isDown("left") and 1 or 0)
    local dy = (input:isDown("down") and 1 or 0)
             - (input:isDown("up") and 1 or 0)
    return dx, dy
  end

  local function flyDirectionalEdge(input)
    return input:wasPressed("up") or input:wasPressed("down")
        or input:wasPressed("left") or input:wasPressed("right")
  end

  function FlyCrosshair:beginRepeat(dx, dy)
    self.repeatDX = dx or 0
    self.repeatDY = dy or 0
    self.repeatElapsed = 0
    self.repeatNext = FLY_HOLD_DELAY
  end

  function FlyCrosshair:clearRepeat()
    self.repeatDX = 0
    self.repeatDY = 0
    self.repeatElapsed = 0
    self.repeatNext = FLY_HOLD_DELAY
  end

  function FlyCrosshair:update(dt)
    self.blink = (self.blink + 1) % 32
    if self.base then self.base.blink = self.blink end
    local input = self.game.input

    if input:wasPressed("b") then
      FlySound.play(self.game.data, "Press_AB")
      self.game.stack:pop()
      return
    end

    if input:wasPressed("a") then
      local target = self:target()
      if target then
        FlySound.play(self.game.data, "Press_AB")
        self.game.stack:pop()
        if self.onFly then self.onFly(target.mapId) end
      end
      return
    end

    local dx, dy = flyHeldVector(input)

    if flyDirectionalEdge(input) and (dx ~= 0 or dy ~= 0) then
      local wasMoving = self.repeatDX ~= 0 or self.repeatDY ~= 0
      self:move(dx, dy)
      if wasMoving then
        self.repeatDX, self.repeatDY = dx, dy
        self.repeatElapsed = 0
        self.repeatNext = FLY_REPEAT_INTERVAL
      else
        self:beginRepeat(dx, dy)
      end
      return
    end

    if dx == 0 and dy == 0 then
      self:clearRepeat()
      return
    end

    if dx ~= self.repeatDX or dy ~= self.repeatDY then
      local wasMoving = self.repeatDX ~= 0 or self.repeatDY ~= 0
      self.repeatDX, self.repeatDY = dx, dy
      if not wasMoving then
        self.repeatElapsed = 0
        self.repeatNext = FLY_HOLD_DELAY
      end
    end

    self.repeatElapsed = self.repeatElapsed + (tonumber(dt) or (1 / 60))
    while self.repeatElapsed >= self.repeatNext do
      self:move(dx, dy)
      self.repeatNext = self.repeatNext + FLY_REPEAT_INTERVAL
      if self.repeatNext < self.repeatElapsed - FLY_REPEAT_INTERVAL then
        self.repeatNext = self.repeatElapsed + FLY_REPEAT_INTERVAL
      end
    end
  end

  local function flyMarkerXY(screen)
    if screen.base and screen.base.mode == "grid" and screen.base.bg then
      return screen.x * 8 + 16, screen.y * 8 + 8
    end
    return screen.x * 8, screen.y * 8
  end

  function FlyCrosshair:draw()
    local base = self.base
    if base then

      local oldSel = base.sel
      base.sel = 0
      base:draw()
      base.sel = oldSel
    else
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
    end

    local Font = mod.ui.Font
    local target = self:target()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 8)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(target and ("To " .. target.name) or "FLY", 8, 0)

    if self.blink % 16 < 10 then
      local x, y = flyMarkerXY(self)
      if base and base.bg and base.bg.cursor then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(base.bg.cursor, x - 4, y - 4)
      else
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, 7, 7)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function decorateBuiltinExtraFly(screen, game)
    if not (screen and screen.fly and extraFlyEnabled()) then return screen end
    for i, mapId in ipairs(screen.flyMapIds or {}) do
      local extra = EXTRA_FLY[mapId]
      local loc = screen.locs and screen.locs[i]
      if extra and loc then
        local x, y = extraFlyMarkerCoords(game, mapId)
        local shown = { name = extra.name, x = loc.x, y = loc.y }
        if x and y then shown.x, shown.y = x, y end
        screen.locs[i] = shown
      end
    end
    return screen
  end

  local function newBuiltinTownMap(game, opts)
    if opts and opts.fly and extraFlyEnabled() then
      syncMtMoonFlyLanding(game)
      syncRockTunnelFlyLanding(game)
    end
    local screen = BuiltinTownMap.new(game, opts)
    if opts and opts.fly then decorateBuiltinExtraFly(screen, game) end
    return screen
  end

  mod.content.screens:register("TownMap", {
    new = function(game, opts)
      if opts and opts.fly and featureOn("free_fly_map") then
        return newFlyCrosshair(game, opts)
      end
      return newBuiltinTownMap(game, opts)
    end,
  })

  local HM_MOVES = {
    CUT = true,
    FLY = true,
    SURF = true,
    STRENGTH = true,
    FLASH = true,
  }

  local function isHMMove(moveId)
    local configured = mod.content.constants:get("hmMoves")
    if type(configured) == "table" then
      if configured[moveId] == true then return true end
      for _, row in ipairs(configured) do
        local id = type(row) == "table" and row.id or row
        if id == moveId then return true end
      end
    end
    return HM_MOVES[moveId] == true
  end

  do
    local MoveLearnMenu = require("src.ui.MoveLearnMenu")
    local ORIGINAL_KEY = "_menuQoL_hmForgetOriginalUpdate"
    local DISPATCH_KEY = "_menuQoL_hmForgetDispatch"
    local WRAPPED_KEY = "_menuQoL_hmForgetWrapped"

    if not MoveLearnMenu[ORIGINAL_KEY] then
      MoveLearnMenu[ORIGINAL_KEY] = MoveLearnMenu.update
    end

    MoveLearnMenu[DISPATCH_KEY] = function(self)
      if not featureOn("forgettable_hms") then return false end
      if not (self and self.selecting and self.game and self.game.input) then
        return false
      end
      if not self.game.input:wasPressed("a") then return false end
      if not (self.mon and self.mon.moves and self.index
          and self.index <= #self.mon.moves) then
        return false
      end

      local old = self.mon.moves[self.index]
      if not (old and isHMMove(old.id)) then return false end

      local mdef = self.game.data.moves[self.newMoveId]
      if not mdef then return false end
      self.mon.moves[self.index] = { id = self.newMoveId, pp = mdef.pp or 0 }
      local oldDef = self.game.data.moves[old.id]
      self.forgot = (oldDef and oldDef.name) or tostring(old.id)
      self:finish(true)
      return true
    end

    if not MoveLearnMenu[WRAPPED_KEY] then
      MoveLearnMenu[WRAPPED_KEY] = true
      MoveLearnMenu.update = function(self, dt)
        local dispatch = MoveLearnMenu[DISPATCH_KEY]
        if dispatch and dispatch(self, dt) then return end
        return MoveLearnMenu[ORIGINAL_KEY](self, dt)
      end
    end
  end

  local function monName(game, mon)
    if not mon then return "POKEMON" end
    if mon.nickname and mon.nickname ~= "" then return mon.nickname end
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[mon.species]
    return (def and def.name) or tostring(mon.species or "POKEMON")
  end

  local function historyFor(mon)
    if not mon then return nil end

    if mon.extra == nil then
      mon.extra = {}
    elseif type(mon.extra) ~= "table" then
      return nil
    end

    local history = mon.extra[HISTORY_FIELD]
    if type(history) ~= "table" then
      history = {
        version = HISTORY_VERSION,
        moves = {},
        seededSpecies = {},
      }
      mon.extra[HISTORY_FIELD] = history
    end

    if type(history.moves) ~= "table" then history.moves = {} end
    if type(history.seededSpecies) ~= "table" then history.seededSpecies = {} end
    history.version = HISTORY_VERSION
    return history
  end

  local function contains(list, value)
    for _, existing in ipairs(list or {}) do
      if existing == value then return true end
    end
    return false
  end

  local function rememberMove(mon, moveId, data)
    if not (mon and moveId) then return end
    if data and data.moves and not data.moves[moveId] then return end

    local history = historyFor(mon)
    if not history or contains(history.moves, moveId) then return end
    history.moves[#history.moves + 1] = moveId
  end

  local function rememberCurrentMoves(game, mon)
    if not mon then return end
    for _, move in ipairs(mon.moves or {}) do
      rememberMove(mon, move.id, game and game.data)
    end
  end

  local function deltaCombinedLearnset(game, mon, speciesId)
    local other = mod.find("deltas")
    local exports = other and other.exports
    local getCombined = exports and exports.getCombinedLearnset
    if type(getCombined) ~= "function" then return nil end

    local probe = mon
    if speciesId ~= mon.species then
      probe = {
        species = speciesId,
        level = mon.level,
        extra = mon.extra,
      }
    end

    local ok, rows = pcall(getCombined, game.data, probe)
    if ok and type(rows) == "table" then return rows end

    if not warnedDeltaApi then
      warnedDeltaApi = true
      mod.log:warn(
        "Delta framework is installed, but getCombinedLearnset failed; falling back to the base learnset"
      )
    end
    return nil
  end

  local function seedSpeciesMoves(game, mon, speciesId)
    if not (game and game.data and mon and speciesId) then return end
    local history = historyFor(mon)
    if not history or history.seededSpecies[speciesId] then return end

    local def = game.data.pokemon and game.data.pokemon[speciesId]
    if not def then return end

    for _, moveId in ipairs(def.level1Moves or {}) do
      rememberMove(mon, moveId, game.data)
    end

    local rows = deltaCombinedLearnset(game, mon, speciesId)
      or def.learnset
      or {}

    local level = mon.level or 1
    for _, entry in ipairs(rows) do
      if entry.level and entry.level <= level then
        rememberMove(mon, entry.move, game.data)
      end
    end

    history.seededSpecies[speciesId] = true
  end

  local function syncHistory(game, mon)
    if not (game and mon) then return end
    seedSpeciesMoves(game, mon, mon.species)
    rememberCurrentMoves(game, mon)
  end

  local function knowsMove(mon, moveId)
    for _, move in ipairs((mon and mon.moves) or {}) do
      if move.id == moveId then return true end
    end
    return false
  end

  local function relearnableMoves(game, mon)
    syncHistory(game, mon)
    local history = historyFor(mon)
    local out = {}
    if not history then return out end

    for _, moveId in ipairs(history.moves) do
      if game.data.moves[moveId] and not knowsMove(mon, moveId) then
        out[#out + 1] = moveId
      end
    end
    return out
  end

  local function pushMessage(game, text, onDone)
    game.stack:push(mod.ui.TextBox.new(game, text, onDone))
  end

  local function learnedMessage(game, mon, moveId)
    local move = game.data.moves[moveId]
    return ("%s learned\n%s!"):format(monName(game, mon), move.name)
  end

  local function forgottenAndLearnedMessage(game, mon, oldMoveId, newMoveId)
    local oldMove = game.data.moves[oldMoveId]
    local newMove = game.data.moves[newMoveId]
    return ("%s forgot\n%s!\f%s learned\n%s!"):format(
      monName(game, mon),
      oldMove and oldMove.name or tostring(oldMoveId),
      monName(game, mon),
      newMove.name
    )
  end

  local function relearnPP(existingPP, newDef)
    local current = math.max(0, math.floor(tonumber(existingPP) or 0))
    local maximum = math.max(0, math.floor(tonumber(newDef and newDef.pp) or 0))
    return math.min(current, maximum)
  end

  local function learnIntoFreeSlot(game, mon, moveId)
    local move = game.data.moves[moveId]
    if not move then return end
    mon.moves = mon.moves or {}
    mon.moves[#mon.moves + 1] = { id = moveId, pp = 0 }
    rememberMove(mon, moveId, game.data)
    pushMessage(game, learnedMessage(game, mon, moveId))
  end

  local function pushForgetMenu(game, mon, newMoveId, relearnMenu)
    local items = {}
    for index, move in ipairs(mon.moves or {}) do
      local def = game.data.moves[move.id]
      items[#items + 1] = {
        label = (def and def.name) or tostring(move.id),
        value = index,
      }
    end
    items[#items + 1] = { label = "CANCEL", cancel = true }

    local forgetMenu = mod.ui.ListMenu.new(game, "FORGET WHICH?", items, {
      wrap = true,
      onChoose = function(item, menu)
        if item.cancel then
          menu:close()
          return
        end

        local slot = item.value
        local oldMove = mon.moves and mon.moves[slot]
        if not oldMove then return end

        if isHMMove(oldMove.id) and not featureOn("forgettable_hms") then
          pushMessage(game, "HM techniques\ncan't be deleted!")
          return
        end

        local newDef = game.data.moves[newMoveId]
        if not newDef then return end

        local oldMoveId = oldMove.id
        local carriedPP = relearnPP(oldMove.pp, newDef)
        rememberMove(mon, oldMoveId, game.data)
        mon.moves[slot] = { id = newMoveId, pp = carriedPP }
        rememberMove(mon, newMoveId, game.data)

        menu:close()
        if relearnMenu then relearnMenu:close() end
        pushMessage(game,
          forgottenAndLearnedMessage(game, mon, oldMoveId, newMoveId))
      end,
    })

    game.stack:push(forgetMenu)
  end

  local function pushRelearnMenu(game, mon)
    local candidates = relearnableMoves(game, mon)
    if #candidates == 0 then
      pushMessage(game, "No moves to\nrelearn.")
      return
    end

    local items = {}
    for _, moveId in ipairs(candidates) do
      local def = game.data.moves[moveId]
      items[#items + 1] = {
        label = def.name,
        right = "PP " .. tostring(def.pp or 0),
        value = moveId,
      }
    end

    local relearnMenu = mod.ui.ListMenu.new(game, "RELEARN", items, {
      pageJump = true,
      keyRepeat = true,
      wrap = true,
      onChoose = function(item, menu)
        local moveId = item.value
        if not moveId or knowsMove(mon, moveId) then return end

        if #(mon.moves or {}) < 4 then
          menu:close()
          learnIntoFreeSlot(game, mon, moveId)
        else
          pushForgetMenu(game, mon, moveId, menu)
        end
      end,
    })

    game.stack:push(relearnMenu)
  end

  local function pushNicknameScreen(game, mon)
    local oldNickname = mon.nickname
    game.stack:push(mod.ui.NamingScreen.new(game, {
      title = "RENAME?",
      maxLen = 10,
      default = oldNickname,
      onDone = function(name)
        if name and name ~= "" then
          mon.nickname = name
        elseif oldNickname == nil then
          mon.nickname = nil
        end
      end,
    }))
  end

  mod.events:on("game.ready", function(ev)
    liveGame = ev and ev.game or liveGame
  end)

  mod.events:on("pokemon.move_learned", function(ev)
    if ev and ev.mon and ev.moveId then
      rememberMove(ev.mon, ev.moveId, liveGame and liveGame.data)
    end
  end)

  mod.events:on("pokemon.evolved", function(ev)
    if not (liveGame and ev and ev.mon) then return end
    if ev.fromSpecies then seedSpeciesMoves(liveGame, ev.mon, ev.fromSpecies) end
    if ev.toSpecies then seedSpeciesMoves(liveGame, ev.mon, ev.toSpecies) end
    rememberCurrentMoves(liveGame, ev.mon)
  end)

  do
    local BattleState = require("src.battle.BattleState")
    local Timing = require("src.core.Timing")

    local HP_ORIGINAL = "__menuQoLFasterBattlesOriginalStepHPDrain"
    local HP_DISPATCH = "__menuQoLFasterBattlesStepHPDrainDispatch"
    local HP_WRAPPED = "__menuQoLFasterBattlesStepHPDrainWrapped"

    if not BattleState[HP_ORIGINAL] then
      BattleState[HP_ORIGINAL] = BattleState.stepHPDrain
    end
    if not BattleState[HP_WRAPPED] then
      BattleState[HP_WRAPPED] = true
      BattleState.stepHPDrain = function(self)
        local dispatch = BattleState[HP_DISPATCH]
        if type(dispatch) == "function" then return dispatch(self) end
        return BattleState[HP_ORIGINAL](self)
      end
    end

    BattleState[HP_DISPATCH] = function(self)
      if not featureOn("faster_battles") then
        return BattleState[HP_ORIGINAL](self)
      end
      local previous = Timing.HP_BAR_PIXEL_STEP
      Timing.HP_BAR_PIXEL_STEP = 1
      local ok, result = pcall(BattleState[HP_ORIGINAL], self)
      Timing.HP_BAR_PIXEL_STEP = previous
      if not ok then error(result, 0) end
      return result
    end

    local BLINK_ORIGINAL = "__menuQoLFasterBattlesOriginalApplyHitFx"
    local BLINK_DISPATCH = "__menuQoLFasterBattlesApplyHitFxDispatch"
    local BLINK_WRAPPED = "__menuQoLFasterBattlesApplyHitFxWrapped"

    if not BattleState[BLINK_ORIGINAL] then
      BattleState[BLINK_ORIGINAL] = BattleState.applyHitFx
    end
    if not BattleState[BLINK_WRAPPED] then
      BattleState[BLINK_WRAPPED] = true
      BattleState.applyHitFx = function(self, hit)
        local dispatch = BattleState[BLINK_DISPATCH]
        if type(dispatch) == "function" then return dispatch(self, hit) end
        return BattleState[BLINK_ORIGINAL](self, hit)
      end
    end

    BattleState[BLINK_DISPATCH] = function(self, hit)
      if not featureOn("faster_battles") then
        return BattleState[BLINK_ORIGINAL](self, hit)
      end
      local previous = Timing.BLINK_MON
      Timing.BLINK_MON = 40
      local ok, result = pcall(BattleState[BLINK_ORIGINAL], self, hit)
      Timing.BLINK_MON = previous
      if not ok then error(result, 0) end
      return result
    end
  end


  do
    local BattleState = require("src.battle.BattleState")
    local Damage = require("src.battle.Damage")

    local function applyAccuracyStage(value, stage)
      stage = math.max(-6, math.min(6, tonumber(stage) or 0))
      if stage >= 0 then
        return math.floor(value * (2 + stage) / 2)
      end
      return math.floor(value * 2 / (2 - stage))
    end

    local function accuracyThresholdCompat(ruleset, move, attacker, defender)
      if type(Damage.accuracyThreshold) == "function" then
        local ok, value = pcall(Damage.accuracyThreshold,
          ruleset, move, attacker, defender)
        if ok and type(value) == "number" then return value end
      end
      if not (move and attacker and defender) then return nil end
      if attacker.xAccuracy then return 256 end
      local moveAccuracy = tonumber(move.accuracy)
      if not moveAccuracy then return nil end
      local accuracyStage = attacker.stages and attacker.stages.accuracy or 0
      local evasionStage = defender.stages and defender.stages.evasion or 0
      local acc = math.floor(moveAccuracy * 255 / 100)
      acc = math.min(255, applyAccuracyStage(acc, accuracyStage))
      acc = math.min(255, applyAccuracyStage(acc, -evasionStage))
      if ruleset and ruleset.oneIn256Miss == false and moveAccuracy >= 100
          and accuracyStage >= evasionStage then
        return 256
      end
      return acc
    end

    local function battlerDisplayName(battler)
      if not battler then return "POKEMON" end
      local name = battler.name or (battler.mon and battler.mon.nickname) or "POKEMON"
      return battler.isPlayer and name or ("Enemy " .. name)
    end

    local BALL_ORIGINAL = "__menuQoLBetterBattlesOriginalBallMissMessage"
    local BALL_DISPATCH = "__menuQoLBetterBattlesBallMissDispatch"
    local BALL_WRAPPED = "__menuQoLBetterBattlesBallMissWrapped"
    if not BattleState[BALL_ORIGINAL] then
      BattleState[BALL_ORIGINAL] = BattleState.ballMissMessage
    end
    if not BattleState[BALL_WRAPPED] then
      BattleState[BALL_WRAPPED] = true
      BattleState.ballMissMessage = function(self, shakes)
        local dispatch = BattleState[BALL_DISPATCH]
        if type(dispatch) == "function" then
          local replacement = dispatch(self, shakes)
          if replacement ~= nil then return replacement end
        end
        return BattleState[BALL_ORIGINAL](self, shakes)
      end
    end
    BattleState[BALL_DISPATCH] = function(self, shakes)
      if featureOn("faster_battles") and shakes == 0 and self.kind == "wild" then
        return "It's too strong!"
      end
      return nil
    end

    local ACC_ORIGINAL = "__menuQoLBetterBattlesOriginalAccuracyRoll"
    local ACC_DISPATCH = "__menuQoLBetterBattlesAccuracyDispatch"
    local ACC_WRAPPED = "__menuQoLBetterBattlesAccuracyWrapped"
    if not BattleState[ACC_ORIGINAL] then
      BattleState[ACC_ORIGINAL] = BattleState.accuracyRoll
    end
    if not BattleState[ACC_WRAPPED] then
      BattleState[ACC_WRAPPED] = true
      BattleState.accuracyRoll = function(self, move, user, target)
        local dispatch = BattleState[ACC_DISPATCH]
        if type(dispatch) == "function" then
          return dispatch(self, move, user, target)
        end
        return BattleState[ACC_ORIGINAL](self, move, user, target)
      end
    end
    BattleState[ACC_DISPATCH] = function(self, move, user, target)
      self.__menuQoLBetterMiss = nil
      local hit = BattleState[ACC_ORIGINAL](self, move, user, target)
      if featureOn("faster_battles") and not hit and move and user and target then
        local threshold = accuracyThresholdCompat(self.ruleset, move, user, target)
        if (tonumber(move.accuracy) or 0) >= 100 and threshold == 255 then
          self.__menuQoLBetterMiss = { kind = "one_in_256", target = target }
        end
      end
      return hit
    end

    local DAMAGE_ORIGINAL = "__menuQoLBetterBattlesOriginalComputeDamage"
    local DAMAGE_DISPATCH = "__menuQoLBetterBattlesDamageDispatch"
    local DAMAGE_WRAPPED = "__menuQoLBetterBattlesDamageWrapped"
    if not BattleState[DAMAGE_ORIGINAL] then
      BattleState[DAMAGE_ORIGINAL] = BattleState.computeDamage
    end
    if not BattleState[DAMAGE_WRAPPED] then
      BattleState[DAMAGE_WRAPPED] = true
      BattleState.computeDamage = function(self, user, target, move, opts)
        local dispatch = BattleState[DAMAGE_DISPATCH]
        if type(dispatch) == "function" then
          return dispatch(self, user, target, move, opts)
        end
        return BattleState[DAMAGE_ORIGINAL](self, user, target, move, opts)
      end
    end
    BattleState[DAMAGE_DISPATCH] = function(self, user, target, move, opts)
      self.__menuQoLBetterMiss = nil
      local damage, info = BattleState[DAMAGE_ORIGINAL](self, user, target, move, opts)
      if featureOn("faster_battles") and info and info.missed == true then
        self.__menuQoLBetterMiss = { kind = "zero_damage", target = target }
      end
      return damage, info
    end

    local SAY_ORIGINAL = "__menuQoLBetterBattlesOriginalSayNext"
    local SAY_DISPATCH = "__menuQoLBetterBattlesSayNextDispatch"
    local SAY_WRAPPED = "__menuQoLBetterBattlesSayNextWrapped"
    if not BattleState[SAY_ORIGINAL] then
      BattleState[SAY_ORIGINAL] = BattleState.sayNext
    end
    if not BattleState[SAY_WRAPPED] then
      BattleState[SAY_WRAPPED] = true
      BattleState.sayNext = function(self, message)
        local dispatch = BattleState[SAY_DISPATCH]
        if type(dispatch) == "function" then
          message = dispatch(self, message)
        end
        return BattleState[SAY_ORIGINAL](self, message)
      end
    end
    BattleState[SAY_DISPATCH] = function(self, message)
      local reason = self.__menuQoLBetterMiss
      if not (featureOn("faster_battles") and reason) then return message end
      self.__menuQoLBetterMiss = nil
      if reason.kind == "one_in_256" then
        return battlerDisplayName(reason.target) .. "\nevaded the attack!"
      elseif reason.kind == "zero_damage" then
        return "The attack didn't\nleave a scratch!"
      end
      return message
    end
  end

  do
    local AnimPlayer = require("src.battle.AnimPlayer")
    local BattleState = require("src.battle.BattleState")

    local function rgb(r, g, b)
      return { r / 255, g / 255, b / 255 }
    end

    local TYPE_ATTACK_PALETTES = {
      NORMAL = { rgb(236,236,232), rgb(164,164,156), rgb(84,84,80) },
      FIGHTING = { rgb(248,176,132), rgb(202,86,58), rgb(112,42,32) },
      FLYING = { rgb(204,230,255), rgb(112,164,232), rgb(58,88,156) },
      POISON = { rgb(230,170,242), rgb(168,76,186), rgb(92,42,112) },
      GROUND = { rgb(246,220,146), rgb(198,150,62), rgb(116,82,28) },
      ROCK = { rgb(236,218,160), rgb(180,150,72), rgb(104,78,30) },
      BUG = { rgb(220,238,116), rgb(158,186,32), rgb(78,104,18) },
      GHOST = { rgb(204,184,238), rgb(112,88,164), rgb(58,42,96) },
      STEEL = { rgb(224,236,244), rgb(142,164,180), rgb(72,92,108) },
      FIRE = { rgb(255,170,132), rgb(238,64,42), rgb(142,24,18) },
      WATER = { rgb(156,210,255), rgb(54,130,232), rgb(18,66,146) },
      GRASS = { rgb(190,242,154), rgb(78,184,70), rgb(30,106,38) },
      ELECTRIC = { rgb(255,246,142), rgb(248,210,36), rgb(166,118,0) },
      PSYCHIC = { rgb(255,170,210), rgb(226,74,138), rgb(132,38,86) },
      PSYCHIC_TYPE = { rgb(255,170,210), rgb(226,74,138), rgb(132,38,86) },
      ICE = { rgb(190,246,255), rgb(76,204,230), rgb(28,112,142) },
      DRAGON = { rgb(194,178,255), rgb(104,78,224), rgb(54,36,144) },
      DARK = { rgb(190,178,174), rgb(102,82,78), rgb(44,34,36) },
      FAIRY = { rgb(255,206,232), rgb(238,126,180), rgb(154,60,112) },
      BIRD = { rgb(204,230,255), rgb(112,164,232), rgb(58,88,156) },
    }

    local function hsv(h, s, v)
      local i = math.floor(h * 6)
      local f = h * 6 - i
      local p = v * (1 - s)
      local q = v * (1 - f * s)
      local t = v * (1 - (1 - f) * s)
      i = i % 6
      local r, g, b
      if i == 0 then r,g,b = v,t,p
      elseif i == 1 then r,g,b = q,v,p
      elseif i == 2 then r,g,b = p,v,t
      elseif i == 3 then r,g,b = p,q,v
      elseif i == 4 then r,g,b = t,p,v
      else r,g,b = v,p,q end
      return { r, g, b }
    end

    local generatedPalettes = {}
    local function attackPalette(typeId)
      if not typeId then return nil end
      local key = tostring(typeId):upper()
      local known = TYPE_ATTACK_PALETTES[key]
      if known then return known end
      if generatedPalettes[key] then return generatedPalettes[key] end
      local hash = 0
      for i = 1, #key do hash = (hash * 33 + key:byte(i)) % 360 end
      local h = hash / 360
      local p = { hsv(h, 0.36, 1.00), hsv(h, 0.64, 0.78), hsv(h, 0.78, 0.42) }
      generatedPalettes[key] = p
      return p
    end

    local function spritePalette(base, sprite)
      local key = sprite and sprite.obp or "f0"
      if key == "obp1" then return { base[3], base[2], base[1] } end
      if key == "f0x" or key == "e4x" then return { base[2], base[1], base[3] } end
      return base
    end

    local START_ORIGINAL = "__menuQoLColorAttacksOriginalStart"
    local START_DISPATCH = "__menuQoLColorAttacksStartDispatch"
    local START_WRAPPED = "__menuQoLColorAttacksStartWrapped"
    if not AnimPlayer[START_ORIGINAL] then
      AnimPlayer[START_ORIGINAL] = AnimPlayer.start
    end
    if not AnimPlayer[START_WRAPPED] then
      AnimPlayer[START_WRAPPED] = true
      AnimPlayer.start = function(self, moveId, attackerIsPlayer, opts)
        local dispatch = AnimPlayer[START_DISPATCH]
        if type(dispatch) == "function" then
          return dispatch(self, moveId, attackerIsPlayer, opts)
        end
        return AnimPlayer[START_ORIGINAL](self, moveId, attackerIsPlayer, opts)
      end
    end
    AnimPlayer[START_DISPATCH] = function(self, moveId, attackerIsPlayer, opts)
      self.__menuQoLAnimationId = moveId
      return AnimPlayer[START_ORIGINAL](self, moveId, attackerIsPlayer, opts)
    end

    local DRAW_ORIGINAL = "__menuQoLColorAttacksOriginalDrawAnimLayer"
    local DRAW_DISPATCH = "__menuQoLColorAttacksDrawAnimLayerDispatch"
    local DRAW_WRAPPED = "__menuQoLColorAttacksDrawAnimLayerWrapped"
    if not BattleState[DRAW_ORIGINAL] then
      BattleState[DRAW_ORIGINAL] = BattleState.drawAnimLayer
    end
    if not BattleState[DRAW_WRAPPED] then
      BattleState[DRAW_WRAPPED] = true
      BattleState.drawAnimLayer = function(self, colorized)
        local dispatch = BattleState[DRAW_DISPATCH]
        if type(dispatch) == "function" then return dispatch(self, colorized) end
        return BattleState[DRAW_ORIGINAL](self, colorized)
      end
    end

    BattleState[DRAW_DISPATCH] = function(self, colorized)
      if not featureOn("color_attacks") or not self.animPlaying or not self.animPlayer then
        return BattleState[DRAW_ORIGINAL](self, colorized)
      end

      local animId = self.animPlayer.__menuQoLAnimationId
      local move = self.data and self.data.moves and self.data.moves[animId]
      local palette = move and attackPalette(move.type)
      if not palette then
        return BattleState[DRAW_ORIGINAL](self, colorized)
      end

      local g = love and love.graphics
      if not g then return BattleState[DRAW_ORIGINAL](self, colorized) end
      local PaletteFX = require("src.render.PaletteFX")
      local shader = PaletteFX.shader and PaletteFX.shader() or nil
      if shader then
        g.setColor(1, 1, 1, 1)
        local colorFn = function(sprite)
          return spritePalette(palette, sprite)
        end
        pcall(self.animPlayer.draw, self.animPlayer, colorFn)
      else
        local c = palette[2]
        g.setColor(c[1], c[2], c[3], 1)
        pcall(self.animPlayer.draw, self.animPlayer, nil)
        g.setColor(1, 1, 1, 1)
      end
    end
  end

  local Growth = require("src.pokemon.Growth")

  local function clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
  end

  local function battleExpRatio(battle)
    local game = battle and battle.game or liveGame
    local mon = battle and battle.player and battle.player.mon
    local data = game and game.data
    local def = data and data.pokemon and mon and data.pokemon[mon.species]
    if not (mon and def and def.growthRate) then return nil end

    local level = tonumber(mon.level) or 1
    local levelCap = tonumber(data.constants and data.constants.levelCap) or 100
    if level >= levelCap then return 1 end

    local rates = data.growth_rates
    local floorExp = Growth.expForLevel(def.growthRate, level, rates)
    local nextExp = Growth.expForLevel(def.growthRate, level + 1, rates)
    if type(floorExp) ~= "number" or type(nextExp) ~= "number"
        or nextExp <= floorExp then
      return nil
    end

    return clamp01(((tonumber(mon.exp) or floorExp) - floorExp)
      / (nextExp - floorExp))
  end

  local function battlePlayerHUDVisible(battle)
    if not (battle and battle.player and battle.player.mon) then return false end
    if battle.safari or battle.demo or battle.showPlayerBack or battle.introBalls
        or battle.blankForAskName then
      return false
    end
    if (tonumber(battle.introSlide) or 0) ~= 0 then return false end
    local fx = battle.fx
    if fx and (tonumber(fx.flash) or 0) > 0
        and (tonumber(battle.frame) or 0) % 4 < 2 then
      return false
    end
    if battle.statusHUDVisible and battle:statusHUDVisible() == false then
      return false
    end
    return true
  end

  local function drawBattleExpBar(battle, ratio)
    local g = love and love.graphics
    if not (g and g.rectangle and g.setColor) then return end
    local wide = battle.wideLayout and battle:wideLayout()
    local x, y, w, h = wide and 214 or 80, 89, wide and 86 or 70, 2
    local fx = battle.fx
    local sx, sy = (fx and fx.shakeX) or 0, (fx and fx.shakeY) or 0
    if sx == 0 and sy == 0 and fx and (tonumber(fx.shake) or 0) > 0 then
      sx = (tonumber(battle.frame) or 0) % 4 < 2 and 2 or -2
    end
    x, y = x + sx, y + sy

    local fill = math.floor(w * clamp01(ratio) + 0.5)
    if fill > 0 then
      local drawX = x
      local drawRight = x + fill
      if not wide then
        local coveredRight
        if battle.phase == "moveSelect" then
          coveredRight = 88 + sx
        elseif battle.phase == "mimicSelect" then
          coveredRight = 128 + sx
        end
        if coveredRight then drawX = math.max(drawX, coveredRight) end
      end

      local drawW = drawRight - drawX
      if drawW > 0 then
        g.setColor(0.20, 0.45, 0.95, 1)
        g.rectangle("fill", drawX, y, drawW, h)
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    if not featureOn("battle_xp_bar") then return end
    if not battlePlayerHUDVisible(battle) then return end
    local ratio = battleExpRatio(battle)
    if ratio ~= nil then drawBattleExpBar(battle, ratio) end
  end)

  local REPEL_ITEMS = {
    REPEL = true,
    SUPER_REPEL = true,
    MAX_REPEL = true,
  }
  local REPEL_FALLBACK = { "MAX_REPEL", "SUPER_REPEL", "REPEL" }
  local lastRepelItem = nil

  local function bagCount(game, itemId)
    local inv = game and game.save and game.save.inventory
    return inv and (tonumber(inv[itemId]) or 0) or 0
  end

  local function chooseRepel(game)
    if lastRepelItem and bagCount(game, lastRepelItem) > 0 then
      return lastRepelItem
    end
    for _, itemId in ipairs(REPEL_FALLBACK) do
      if bagCount(game, itemId) > 0 then return itemId end
    end
    return nil
  end

  local function itemDisplayName(game, itemId)
    local def = game and game.data and game.data.items and game.data.items[itemId]
    return (def and def.name) or tostring(itemId):gsub("_", " ")
  end

  local function pushMessages(game, messages)
    if type(messages) ~= "table" or #messages == 0 then return end
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, table.concat(messages, "\f")))
  end

  local function useRepelFromBag(game, itemId)
    if not (game and itemId and bagCount(game, itemId) > 0) then return false end
    local ItemEffects = require("src.inventory.ItemEffects")
    local Bag = require("src.inventory.Bag")
    local result, messages = ItemEffects.use(
      game.data, game.save, itemId, nil, nil, nil, game.overworld)
    if result ~= "consumed" then return false end
    Bag.remove(game.save, itemId, 1)
    lastRepelItem = itemId
    pushMessages(game, messages)
    return true
  end

  local function offerRepelReuse(game)
    if not featureOn("repel_reuse") then return end
    local itemId = chooseRepel(game)
    if not itemId then return end
    local TextBox = require("src.render.TextBox")
    local name = itemDisplayName(game, itemId)
    game.stack:push(TextBox.new(game, "Use another\n" .. name .. "?", nil, {
      choice = function(yes)
        if yes then useRepelFromBag(game, itemId) end
      end,
    }))
  end

  do
    local ItemEffects = require("src.inventory.ItemEffects")
    local ORIGINAL_KEY = "_menuQoL_repelOriginalItemUse"
    local DISPATCH_KEY = "_menuQoL_repelItemUseDispatch"
    local WRAPPED_KEY = "_menuQoL_repelItemUseWrapped"

    if not ItemEffects[ORIGINAL_KEY] then
      ItemEffects[ORIGINAL_KEY] = ItemEffects.use
    end

    ItemEffects[DISPATCH_KEY] = function(_, save, itemId, result)
      if result == "consumed" and REPEL_ITEMS[itemId]
          and save and (tonumber(save.repelSteps) or 0) > 0 then
        lastRepelItem = itemId
      end
    end

    if not ItemEffects[WRAPPED_KEY] then
      ItemEffects[WRAPPED_KEY] = true
      ItemEffects.use = function(data, save, itemId, target, battle, moveIndex, ow)
        local result, messages, extra = ItemEffects[ORIGINAL_KEY](
          data, save, itemId, target, battle, moveIndex, ow)
        local dispatch = ItemEffects[DISPATCH_KEY]
        if dispatch then dispatch(data, save, itemId, result, messages, extra) end
        return result, messages, extra
      end
    end
  end

  do
    local OverworldState = require("src.world.OverworldController")
    local ORIGINAL_KEY = "_menuQoL_repelOriginalStepComplete"
    local DISPATCH_KEY = "_menuQoL_repelStepDispatch"
    local WRAPPED_KEY = "_menuQoL_repelStepWrapped"

    if not OverworldState[ORIGINAL_KEY] then
      OverworldState[ORIGINAL_KEY] = OverworldState.onStepComplete
    end

    OverworldState[DISPATCH_KEY] = function(beforeSteps, self, game)
      if not featureOn("repel_reuse") then return end
      game = game or liveGame or mod.game or (self and self.game)
      if not (game and game.save and game.stack) then return end
      local afterSteps = tonumber(game.save.repelSteps) or 0
      if (tonumber(beforeSteps) or 0) <= 0 or afterSteps ~= 0 then return end

      local top
      if type(game.stack.top) == "function" then
        top = game.stack:top()
      elseif type(game.stack.states) == "table" then
        top = game.stack.states[#game.stack.states]
      end
      if type(top) ~= "table" or top.__menuQoLRepelReuseAttached then return end
      top.__menuQoLRepelReuseAttached = true
      local previousDone = top.onDone
      top.onDone = function(...)
        if previousDone then previousDone(...) end
        offerRepelReuse(game)
      end
    end

    if not OverworldState[WRAPPED_KEY] then
      OverworldState[WRAPPED_KEY] = true
      OverworldState.onStepComplete = function(self, ...)
        local game = liveGame or mod.game or (self and self.game)
        local beforeSteps = game and game.save and game.save.repelSteps
        local result = OverworldState[ORIGINAL_KEY](self, ...)
        local dispatch = OverworldState[DISPATCH_KEY]
        if dispatch then dispatch(beforeSteps, self, game) end
        return result
      end
    end
  end

  local function liveOverworld()
    local world = mod.world
    if world and type(world.overworld) == "function" then
      local ok, ow = pcall(world.overworld, world)
      if ok and ow then return ow end
    end

    local game = liveGame or mod.game
    if game and game.overworld then return game.overworld end
    local stack = game and game.stack
    local states = stack and stack.states
    if states then
      for i = #states, 1, -1 do
        if states[i] and states[i].isOverworld then return states[i] end
      end
    end
    return nil
  end

  local function nativeFieldActionAvailable(id, wantedLabel)
    local ow = liveOverworld()
    if not (ow and ow.player) then return nil end

    if id == "cut" then
      if type(ow.useCutFieldMove) ~= "function" then return nil end
      local ok, result = pcall(ow.useCutFieldMove, ow)
      if ok and result == "ok" then return { id = "cut", label = "CUT" } end
      return nil
    elseif id == "surf" then
      if type(ow.useSurfFieldMove) ~= "function" then return nil end
      local ok, result = pcall(ow.useSurfFieldMove, ow)
      if not ok then return nil end
      local label = result == "dismount" and "LEAVE WATER"
                 or result == "ok" and "SURF" or nil
      if label and (wantedLabel == nil or wantedLabel == label) then
        return { id = "surf", label = label }
      end
      return nil
    elseif id == "strength" then
      if ow.strengthActive or type(ow.partyKnows) ~= "function" then return nil end
      local ok, mon = pcall(ow.partyKnows, ow, "STRENGTH")
      if ok and mon then return { id = "strength", label = "STRENGTH" } end
    end
    return nil
  end

  local function availableFieldAction(id, wantedLabel)
    local world = mod.world
    if world and type(world.availableFieldActions) == "function" then
      local ok, actions = pcall(world.availableFieldActions, world)
      if ok and type(actions) == "table" then
        for _, action in ipairs(actions) do
          if action.id == id
              and (wantedLabel == nil or action.label == wantedLabel) then
            return action
          end
        end
        return nil
      end
    end
    return nativeFieldActionAvailable(id, wantedLabel)
  end

  local suppressShortcutSurfFlash = false
  do
    local Transition = require("src.render.Transition")
    local ORIGINAL_KEY = "__menuQoLOriginalWhiteFlash"
    local DISPATCH_KEY = "__menuQoLWhiteFlashDispatch"

    local function noFlashStep(game, onDone)
      local state = { game = game, onDone = onDone, isOpaque = false, done = false }
      function state:update(dt)
        if self.done then return end
        self.done = true
        if self.game and self.game.stack then self.game.stack:pop() end
        if self.onDone then self.onDone() end
      end
      function state:draw() end
      return state
    end

    if not Transition[ORIGINAL_KEY] then
      Transition[ORIGINAL_KEY] = Transition.whiteFlash
      Transition.whiteFlash = function(game, frames, onDone)
        local dispatch = Transition[DISPATCH_KEY]
        if type(dispatch) == "function" then
          local replacement = dispatch(game, frames, onDone)
          if replacement ~= nil then return replacement end
        end
        return Transition[ORIGINAL_KEY](game, frames, onDone)
      end
    end

    Transition[DISPATCH_KEY] = function(game, frames, onDone)
      if not suppressShortcutSurfFlash then return nil end
      local ow = liveOverworld()
      if not (ow and ow.player and ow.player.surfing) then return nil end
      suppressShortcutSurfFlash = false
      return noFlashStep(game, onDone)
    end
  end

  local function useFieldActionCompat(id)
    local world = mod.world
    if world and type(world.useFieldAction) == "function" then
      if id == "surf" then suppressShortcutSurfFlash = true end
      local ok, result = pcall(world.useFieldAction, world, id)
      if ok then
        if result ~= true and id == "surf" then suppressShortcutSurfFlash = false end
        return result == true
      end
      if id == "surf" then suppressShortcutSurfFlash = false end
    end

    local ow = liveOverworld()
    if not (ow and ow.player) then return false end
    if id == "cut" then
      if type(ow.useCutFieldMove) ~= "function" or type(ow.tryCut) ~= "function" then
        return false
      end
      local okCheck, mode = pcall(ow.useCutFieldMove, ow)
      if not okCheck or mode ~= "ok" then return false end
      local fx, fy = ow.player:facingCell()
      local okUse, used = pcall(ow.tryCut, ow, fx, fy)
      return okUse and used == true
    elseif id == "surf" then
      if type(ow.useSurfFieldMove) ~= "function" or type(ow.trySurf) ~= "function" then
        return false
      end
      local okCheck, mode = pcall(ow.useSurfFieldMove, ow)
      if not okCheck or mode ~= "ok" then return false end
      local fx, fy = ow.player:facingCell()
      suppressShortcutSurfFlash = true
      local okUse = pcall(ow.trySurf, ow, fx, fy)
      if not okUse then suppressShortcutSurfFlash = false end
      return okUse
    elseif id == "strength" then
      if type(ow.useStrengthFieldMove) ~= "function" then return false end
      local okUse, used = pcall(ow.useStrengthFieldMove, ow)
      return okUse and used == true
    end
    return false
  end

  mod.events:on("world.interacted", function(ev)
    if not featureOn("field_hm_shortcuts") then return end
    if not (ev and ev.kind == "none" and mod.world) then return end

    if availableFieldAction("cut") then
      useFieldActionCompat("cut")
      return
    end

    if availableFieldAction("surf", "SURF") then
      useFieldActionCompat("surf")
    end
  end)

  local function isPushableObject(def)
    if type(def) ~= "table" then return false end
    if def.pushable ~= nil then return def.pushable == true end
    return def.sprite == "SPRITE_BOULDER"
  end

  do
    local OverworldState = require("src.world.OverworldController")
    local ORIGINAL_KEY = "_menuQoL_party_nickname_relearn_originalTalkTo"
    local DISPATCH_KEY = "_menuQoL_party_nickname_relearn_strengthTalkTo"

    if not OverworldState[ORIGINAL_KEY] then
      OverworldState[ORIGINAL_KEY] = OverworldState.talkTo
      OverworldState.talkTo = function(self, npc)
        local handler = OverworldState[DISPATCH_KEY]
        if type(handler) == "function" and handler(self, npc) then return end
        return OverworldState[ORIGINAL_KEY](self, npc)
      end
    end

    OverworldState[DISPATCH_KEY] = function(_, npc)
      if not featureOn("field_hm_shortcuts") then return false end
      if not isPushableObject(npc and npc.def) then return false end
      if not availableFieldAction("strength") then return false end
      return useFieldActionCompat("strength")
    end
  end

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local out = next(game, items, mon, ctx)
    if type(out) ~= "table" then out = items end

    if ctx and ctx.battle then return out end

    syncHistory(game, mon)

    mod.ui.removeLabel(out, "NICKNAME")
    mod.ui.removeLabel(out, "RENAME")
    mod.ui.removeLabel(out, "RELEARN")

    if featureOn("nickname_button") then
      mod.ui.insertBefore(out, "SWITCH", {
        label = "RENAME",
        onSelect = function(selectedMon, selectedGame)
          pushNicknameScreen(selectedGame or game, selectedMon or mon)
        end,
      })
    end

    if featureOn("relearn_button") then
      mod.ui.insertBefore(out, "SWITCH", {
        label = "RELEARN",
        onSelect = function(selectedMon, selectedGame)
          pushRelearnMenu(selectedGame or game, selectedMon or mon)
        end,
      })
    end

    return out
  end)

  local held = { select = false, start = false }
  local function rising(input, key)
    local down = input and input:isDown(key) == true
    local pressed = down and not held[key]
    held[key] = down
    return pressed
  end

  local function normalFieldPartyMenu(game, state)
    if not (state and state.screenId == "PartyMenu") then return false end
    if state.battle or state.submenu or state.pickOnly or state.tmhm or state.evoStone
        or state.softboiledFrom or state.heal or state.onSwitch then return false end
    local party = state.party or (game.save and game.save.party) or {}
    return #party >= 2 and type(state.index) == "number"
  end

  local function startQuickReorder(game, state)
    if not normalFieldPartyMenu(game, state) and not state.swapFrom then return end
    if state.swapFrom then
      mod.input:tap(game, "a")
    else
      state.swapFrom = state.index
    end
  end

  local function cycleNativeSummary(game, state, delta)
    if not (state and state.mon) then return false end
    local nextMon, nextIndex = adjacentPartyMon(game, state.mon, delta)
    if not nextMon then return false end
    local page = state.page or 1
    game.stack:pop()
    mod.ui.push(game, "SummaryMenu", nextMon)
    local replacement = game.stack:top()
    if replacement and replacement.screenId == "SummaryMenu" then
      replacement.page = page
    end
    game.partyMenuSavedIndex = nextIndex
    return true
  end

  local function openHiddenSummaryPage(game, state)
    if not (game and state and state.mon) then return false end
    mod.ui.push(game, "MenuQoLHiddenStats", state.mon)
    return true
  end

  do
    local ORIGINAL_KEY = "__menuQoLOriginalSummaryUpdate"
    local DISPATCH_KEY = "__menuQoLSummaryUpdateDispatch"
    local WRAPPED_KEY = "__menuQoLSummaryUpdateWrapped"

    if not NativeSummaryMenu[ORIGINAL_KEY] then
      NativeSummaryMenu[ORIGINAL_KEY] = NativeSummaryMenu.update
    end
    if not NativeSummaryMenu[WRAPPED_KEY] then
      NativeSummaryMenu[WRAPPED_KEY] = true
      NativeSummaryMenu.update = function(self, dt)
        local dispatch = NativeSummaryMenu[DISPATCH_KEY]
        if type(dispatch) == "function" and dispatch(self, dt) then return end
        return NativeSummaryMenu[ORIGINAL_KEY](self, dt)
      end
    end

    NativeSummaryMenu[DISPATCH_KEY] = function(self, dt)
      local game = self and self.game
      local input = game and game.input
      if not input then return false end

      if featureOn("summary_party_cycle") then
        if input:wasPressed("up") then
          cycleNativeSummary(game, self, -1)
          return true
        elseif input:wasPressed("down") then
          cycleNativeSummary(game, self, 1)
          return true
        elseif input:wasPressed("left") then
          if self.page == 2 then
            if featureOn("hidden_stats") then
              openHiddenSummaryPage(game, self)
            else
              self.page = 1
            end
          end
          return true
        elseif input:wasPressed("right") then
          if self.page == 1 then
            if featureOn("hidden_stats") then
              openHiddenSummaryPage(game, self)
            else
              self.page = 2
            end
          end
          return true
        end
      end

      if featureOn("hidden_stats") and self.page == 1
          and (input:wasPressed("a") or input:wasPressed("b")) then
        openHiddenSummaryPage(game, self)
        return true
      end

      return false
    end
  end

  mod.hooks:wrap("input.step", function(next, game, dt)
    local input = game and game.input
    if not input then return next(game, dt) end

    local selectPressed = rising(input, "select")
    local startPressed = rising(input, "start")
    local state = game.stack and game.stack:top()

    if featureOn("quick_party_reorder") and selectPressed
        and state and state.screenId == "PartyMenu" then
      startQuickReorder(game, state)
    elseif state and state.screenId == "SummaryMenu" and state.mon
        and featureOn("expanded_move_info") and state.page == 2
        and (startPressed or selectPressed) then
      mod.ui.push(game, "MenuQoLMoveDetails", state.mon)
    end

    return next(game, dt)
  end)

  mod.exports.swuff_api_version = 1
  mod.exports.swuffRememberMove = function(mon, moveId, data)
    rememberMove(mon, moveId, data or (liveGame and liveGame.data))
  end
  mod.exports.swuffRelearnableMoves = function(game, mon)
    return relearnableMoves(game or liveGame, mon)
  end
end
