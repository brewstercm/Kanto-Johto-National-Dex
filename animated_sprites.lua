-- Animated battle / Pokédex / summary sprites from horizontal PNG strips.
-- Each strip is pre-cropped and normalized at build time; data/anim_meta.lua
-- records its frame width/height/count. Frames are cut in memory lazily so
-- the archive keeps one compact PNG per species/side instead of tens of
-- thousands of individual files.
return function(mod, dexArt, animMeta, shinyAnimMeta, runningGen1)
  local FPS = 12
  local MAX_SETS = 18
  local KEEP_SETS = 12
  local cache, cacheCount, tick = {}, 0, 0
  local isAnimImage = setmetatable({}, { __mode = "k" })

  local function shinyState(mon)
    if type(mon) ~= "table" then return false end
    if mon.shiny then return true end
    local dvs = mon.dvs
    if type(dvs) ~= "table" then return false end
    local attack = tonumber(dvs.attack) or -1
    return tonumber(dvs.defense) == 10 and tonumber(dvs.speed) == 10
      and tonumber(dvs.special) == 10 and (attack % 4 == 2 or attack % 4 == 3)
  end

  local function rowForSpecies(species, shiny)
    local art = species and dexArt[species]
    if not art then return nil, nil end
    local rows = shiny and shinyAnimMeta or animMeta
    return art.dex, rows and rows[art.dex]
  end

  local function sheetPath(dex, side, shiny)
    local variant = shiny and "shiny/" or ""
    return mod.assets:path(("assets/anim/%s%s/%04d.png"):format(
      variant, side, dex))
  end

  local function trimCache(protect)
    if cacheCount <= MAX_SETS then return end
    while cacheCount > KEEP_SETS do
      local oldestKey, oldestUse
      for key, entry in pairs(cache) do
        if key ~= protect and (oldestUse == nil or entry.used < oldestUse) then
          oldestKey, oldestUse = key, entry.used
        end
      end
      if not oldestKey then break end
      cache[oldestKey] = nil
      cacheCount = cacheCount - 1
    end
    collectgarbage("step")
  end

  local function loadSet(dex, side, shiny)
    local rows = shiny and shinyAnimMeta or animMeta
    local m = rows and rows[dex] and rows[dex][side]
    if not m then return nil end
    local key = (shiny and "shiny:" or "normal:") .. side .. ":" .. tostring(dex)
    tick = tick + 1
    local entry = cache[key]
    if entry then
      entry.used = tick
      return entry
    end
    if not (love and love.image and love.image.newImageData
        and love.graphics and love.graphics.newImage) then
      return nil
    end
    local path = sheetPath(dex, side, shiny)
    local ok, data = pcall(love.image.newImageData, path)
    if not (ok and data) then
      if mod.log then mod.log:warn("animated sprite sheet failed: %s", tostring(path)) end
      return nil
    end
    entry = { data = data, frames = {}, meta = m, used = tick, path = path }
    cache[key] = entry
    cacheCount = cacheCount + 1
    trimCache(key)
    return entry
  end

  local function imageAt(dex, side, index, shiny)
    local entry = loadSet(dex, side, shiny)
    if not entry then return nil, nil end
    local m = entry.meta
    index = ((index - 1) % m.count) + 1
    local img = entry.frames[index]
    if img then return img, entry.path end
    local ok, frame = pcall(love.image.newImageData, m.w, m.h)
    if not (ok and frame) then return nil, nil end
    local okPaste = pcall(frame.paste, frame, entry.data,
      0, 0, (index - 1) * m.w, 0, m.w, m.h)
    if not okPaste then return nil, nil end
    local okImage, made = pcall(love.graphics.newImage, frame)
    if not (okImage and made) then return nil, nil end
    if made.setFilter then made:setFilter("nearest", "nearest") end
    entry.frames[index] = made
    isAnimImage[made] = true
    return made, entry.path
  end

  local function frameIndex(dex, count)
    if count <= 1 then return 1 end
    local now = (love and love.timer and love.timer.getTime)
      and love.timer.getTime() or os.clock()
    -- Species offset keeps a screen full of mons from marching in lock-step.
    return (math.floor(now * FPS) + (dex * 7)) % count + 1
  end

  local provider = {}
  function provider:frame(species, side, mon)
    local shiny = shinyState(mon)
    local dex, row = rowForSpecies(species, shiny)
    -- A missing shiny sheet must not blank a sprite. This fallback is also
    -- useful when a future Pokédex expansion lands before its art refresh.
    if not row and shiny then
      shiny = false
      dex, row = rowForSpecies(species, false)
    end
    local m = row and row[side]
    if not (dex and m) then return nil, nil end
    return imageAt(dex, side, frameIndex(dex, m.count), shiny)
  end
  function provider:isAnimatedImage(img) return isAnimImage[img] and true or false end

  -- The strips use modern pixel-art canvases. Keep fronts inside the 7x7
  -- battle box, while Gen 1 backs retain the larger 2x-ish presentation and
  -- Gen 2 backs stay inside its native 6x6 box.
  for species, art in pairs(dexArt) do
    local row = animMeta[art.dex]
    if row and mod.content.pokemon:get(species) then
      local backMax = math.max(row.back.w or 1, row.back.h or 1)
      local backScale
      if runningGen1 then
        backScale = math.min(2, 64 / math.max(1, backMax))
      else
        backScale = math.min(1, 48 / math.max(1, backMax))
      end
      mod.content.pokemon:patch(species, {
        battleScaleFront = 1,
        battleScaleBack = backScale,
        trueColor = true,
      })
    end
  end

  if runningGen1 then
    local okBattle, BattleState = pcall(require, "src.battle.BattleState")
    if okBattle and type(BattleState) == "table" and type(BattleState.update) == "function" then
      BattleState.__kjSheetProvider = provider
      if not BattleState.__kjSheetAnimationHook then
        BattleState.__kjSheetAnimationHook = true
        local innerUpdate = BattleState.update
        BattleState.update = function(self, dt)
          local result = innerUpdate(self, dt)
          local p = BattleState.__kjSheetProvider
          if p then
            if self.player and self.player.mon then
              local img = p:frame(self.player.mon.species, "back", self.player.mon)
              if img then self.player.sprite = img end
            end
            if self.enemy and self.enemy.mon
                and not (self.enemy.name == "GHOST" and self.ghostReal) then
              local img = p:frame(self.enemy.mon.species, "front", self.enemy.mon)
              if img then self.enemy.sprite = img end
            end
          end
          return result
        end
      end
    end

    local okDex, DexEntryMenu = pcall(require, "src.ui.DexEntryMenu")
    if okDex and type(DexEntryMenu) == "table" then
      DexEntryMenu.__kjSheetProvider = provider
      if type(DexEntryMenu.new) == "function" and not DexEntryMenu.__kjSheetNewHook then
        DexEntryMenu.__kjSheetNewHook = true
        local innerNew = DexEntryMenu.new
        DexEntryMenu.new = function(...)
          local self = innerNew(...)
          local p = DexEntryMenu.__kjSheetProvider
          if p and self and self.def then
            local img = p:frame(self.def.id, "front")
            if img then self.sprite, self.spriteTrueColor = img, true end
          end
          return self
        end
      end
      if type(DexEntryMenu.update) == "function" and not DexEntryMenu.__kjSheetUpdateHook then
        DexEntryMenu.__kjSheetUpdateHook = true
        local innerUpdate = DexEntryMenu.update
        DexEntryMenu.update = function(self, dt)
          local result = innerUpdate(self, dt)
          local p = DexEntryMenu.__kjSheetProvider
          if p and self and self.def then
            local img = p:frame(self.def.id, "front")
            if img then self.sprite, self.spriteTrueColor = img, true end
          end
          return result
        end
      end
    end

    local okSummary, SummaryMenu = pcall(require, "src.ui.SummaryMenu")
    if okSummary and type(SummaryMenu) == "table" then
      SummaryMenu.__kjSheetProvider = provider
      if type(SummaryMenu.new) == "function" and not SummaryMenu.__kjSheetNewHook then
        SummaryMenu.__kjSheetNewHook = true
        local innerNew = SummaryMenu.new
        SummaryMenu.new = function(...)
          local self = innerNew(...)
          local p = SummaryMenu.__kjSheetProvider
          if p and self and self.mon then
            local img = p:frame(self.mon.species, "front", self.mon)
            if img then self.sprite, self.spriteTrueColor = img, true end
          end
          return self
        end
      end
      if type(SummaryMenu.update) == "function" and not SummaryMenu.__kjSheetUpdateHook then
        SummaryMenu.__kjSheetUpdateHook = true
        local innerUpdate = SummaryMenu.update
        SummaryMenu.update = function(self, dt)
          local result = innerUpdate(self, dt)
          local p = SummaryMenu.__kjSheetProvider
          if p and self and self.mon then
            local img = p:frame(self.mon.species, "front", self.mon)
            if img then self.sprite, self.spriteTrueColor = img, true end
          end
          return result
        end
      end
    end

    local okEvo, EvolutionState = pcall(require, "src.ui.EvolutionState")
    if okEvo and type(EvolutionState) == "table" then
      EvolutionState.__kjSheetProvider = provider
      local function refreshEvo(self)
        local p = EvolutionState.__kjSheetProvider
        if not (p and self and self.mon) then return end
        local old = p:frame(self.mon.species, "front", self.mon)
        local new = p:frame(self.newSpecies, "front", self.mon)
        if old then self.oldSprite, self.oldSpriteTrueColor = old, true end
        if new then self.newSprite, self.newSpriteTrueColor = new, true end
      end
      if type(EvolutionState.new) == "function" and not EvolutionState.__kjSheetNewHook then
        EvolutionState.__kjSheetNewHook = true
        local innerNew = EvolutionState.new
        EvolutionState.new = function(...)
          local self = innerNew(...)
          refreshEvo(self)
          return self
        end
      end
      if type(EvolutionState.update) == "function" and not EvolutionState.__kjSheetUpdateHook then
        EvolutionState.__kjSheetUpdateHook = true
        local innerUpdate = EvolutionState.update
        EvolutionState.update = function(self, dt)
          local result = innerUpdate(self, dt)
          refreshEvo(self)
          return result
        end
      end
    end
  else
    -- The Gen 2 battle screen resolves its pic every draw, so replacing
    -- pic() is enough to animate both sides without touching battle logic.
    local okBattle, BattleState2 = pcall(require, "src.ui.gen2.BattleState")
    if okBattle and type(BattleState2) == "table" and type(BattleState2.pic) == "function" then
      BattleState2.__kjSheetProvider = provider
      if not BattleState2.__kjSheetAnimationHook then
        BattleState2.__kjSheetAnimationHook = true
        local innerPic = BattleState2.pic
        BattleState2.pic = function(self, mon, back)
          local p = BattleState2.__kjSheetProvider
          if p and mon and mon.species then
            local img, path = p:frame(mon.species, back and "back" or "front", mon)
            if img then return img, true, path end
          end
          return innerPic(self, mon, back)
        end
      end
    end

    local okDex, PokedexMenu2 = pcall(require, "src.ui.gen2.PokedexMenu")
    if okDex and type(PokedexMenu2) == "table" and type(PokedexMenu2.picFor) == "function" then
      PokedexMenu2.__kjSheetProvider = provider
      if not PokedexMenu2.__kjSheetPicHook then
        PokedexMenu2.__kjSheetPicHook = true
        local innerPicFor = PokedexMenu2.picFor
        PokedexMenu2.picFor = function(self, species)
          local p = PokedexMenu2.__kjSheetProvider
          if p and self and self.view == "entry" then
            local img = p:frame(species, "front")
            if img then return img end
          end
          return innerPicFor(self, species)
        end
      end
      if type(PokedexMenu2.drawPic) == "function" and not PokedexMenu2.__kjSheetDrawHook then
        PokedexMenu2.__kjSheetDrawHook = true
        local innerDrawPic = PokedexMenu2.drawPic
        PokedexMenu2.drawPic = function(self, row, tx, ty, ownColors)
          if row and row.seen then
            local image = self:picFor(row.species)
            local p = PokedexMenu2.__kjSheetProvider
            if image and p and p:isAnimatedImage(image) then
              local G = love.graphics
              G.setColor(1, 1, 1, 1)
              G.rectangle("fill", tx * 8, ty * 8, 7 * 8, 7 * 8)
              local w, h = image:getDimensions()
              local x = tx * 8 + math.floor((56 - w) / 2)
              local y = ty * 8 + math.max(0, 56 - h)
              G.draw(image, x, y)
              return
            end
          end
          return innerDrawPic(self, row, tx, ty, ownColors)
        end
      end
    end

    local okSummary, SummaryMenu2 = pcall(require, "src.ui.gen2.SummaryMenu")
    if okSummary and type(SummaryMenu2) == "table" and type(SummaryMenu2.picFor) == "function" then
      SummaryMenu2.__kjSheetProvider = provider
      if not SummaryMenu2.__kjSheetPicHook then
        SummaryMenu2.__kjSheetPicHook = true
        local innerPicFor = SummaryMenu2.picFor
        SummaryMenu2.picFor = function(self, mon)
          local p = SummaryMenu2.__kjSheetProvider
          if p and mon and mon.species then
            local img = p:frame(mon.species, "front", mon)
            if img then return img end
          end
          return innerPicFor(self, mon)
        end
      end
      if type(SummaryMenu2.drawPicBlock) == "function" and not SummaryMenu2.__kjSheetDrawHook then
        SummaryMenu2.__kjSheetDrawHook = true
        local innerDraw = SummaryMenu2.drawPicBlock
        SummaryMenu2.drawPicBlock = function(self, image, colors)
          local p = SummaryMenu2.__kjSheetProvider
          if p and p:isAnimatedImage(image) then colors = nil end
          return innerDraw(self, image, colors)
        end
      end
    end
  end


  -- Keep custom/animated enemy front sprites inside the native enemy picture
  -- safe area.  The engine scales a front pic around its ORIGINAL bottom edge;
  -- for modern canvases taller than 56px that can leave the rendered pixels
  -- hanging over the player's name/level/HP HUD even after the image is scaled
  -- down.  Clamp the rendered bottom to the 7x7 enemy box (y=56) and spend any
  -- extra height upward, where the classic battle layout has room.
  local function installEnemyFrontSafeArea()
    do
      local ok, BattleState = pcall(require, "src.battle.BattleState")
      if ok and type(BattleState) == "table"
         and type(BattleState.frontPlacement) == "function"
         and not BattleState.__customFrontSafeAreaClamp then
        BattleState.__customFrontSafeAreaClamp = true
        local inner = BattleState.frontPlacement
        BattleState.frontPlacement = function(ex, ey, w, h, scale)
          local x, y, s = inner(ex, ey, w, h, scale)
          s = tonumber(s) or tonumber(scale) or 1
          local safeBottom = 56 -- 7 tiles: the stock enemy front-pic box
          local bottom = y + h * s
          if bottom > safeBottom then y = y - (bottom - safeBottom) end
          return x, y, s
        end
      end
    end

    -- The Gen 2 renderer performs the same bottom-edge compensation inside
    -- drawPic rather than through a public placement helper.  Intercept only the
    -- current enemy image's final plain draw and lift it if its rendered bottom
    -- would cross the 7x7 box. Trainer portraits, player backs, substitutes and
    -- cropped faint frames are left to the stock renderer.
    do
      local ok, BattleState = pcall(require, "src.ui.gen2.BattleState")
      if ok and type(BattleState) == "table"
         and type(BattleState.drawPic) == "function"
         and not BattleState.__customFrontSafeAreaClamp then
        BattleState.__customFrontSafeAreaClamp = true
        local inner = BattleState.drawPic
        BattleState.drawPic = function(self, mon, back)
          if back or (self and self.showEnemyTrainer) or not (love and love.graphics) then
            return inner(self, mon, back)
          end
          local image
          if self and type(self.pic) == "function" then
            local okPic, img = pcall(function() return select(1, self:pic(mon, false)) end)
            if okPic then image = img end
          end
          if not image then return inner(self, mon, back) end

          local G = love.graphics
          local originalDraw = G.draw
          local safeBottom = ((BattleState.ENEMY_PIC_TILE_Y or 0)
            + (BattleState.ENEMY_PIC_TILES or 7)) * 8
          G.draw = function(drawable, ...)
            local args = { ... }
            -- Plain Image draw signature: image, x, y, rotation, sx, sy.
            -- Quad/cropped draws (faint animation) intentionally pass through.
            if drawable == image and type(args[1]) == "number" and type(args[2]) == "number" then
              local sy = tonumber(args[5]) or tonumber(args[4]) or 1
              local bottom = args[2] + image:getHeight() * sy
              if bottom > safeBottom then args[2] = args[2] - (bottom - safeBottom) end
            end
            return originalDraw(drawable, unpack(args))
          end
          local okCall, err = pcall(inner, self, mon, back)
          G.draw = originalDraw
          if not okCall then error(err, 0) end
        end
      end
    end
  end
  installEnemyFrontSafeArea()
  mod.events:on("game.ready", installEnemyFrontSafeArea)
  return provider
end
