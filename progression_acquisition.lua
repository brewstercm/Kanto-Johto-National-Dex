-- Cross-generation starter gifts and one-time legendary/mythical encounters.
-- Coordinates are selected from the running cartridge's native map and
-- tileset registries, so R/B/Y and G/S/C each use their own real collision data.
return function(mod, catalog, sprites, gen1, gameVersion)
  assert(type(catalog) == "table", "missing progression special catalog")
  local gen2Profile=(not gen1) and catalog.gen2QuestProfile or nil
  local researchProfessor=(gen2Profile and gen2Profile.professor) or "PROF.OAK"
  local okMapModel,MapModel=pcall(require,"src.world.Map")

  local function sourceMap(base)
    local registered = mod.content.maps:get(base)
    if registered then return registered end
    local data=mod.game and mod.game.data or nil
    if not data then return nil end
    return (data.maps and data.maps[base])
      or (data.gen2Maps and data.gen2Maps[base]) or nil
  end

  local function sourceTileset(def)
    if not def then return nil end
    if type(def.tileset) == "table" then return def.tileset end
    local registered = mod.content.tilesets:get(def.tileset)
    if registered then return registered end
    local data=mod.game and mod.game.data or nil
    if not data then return nil end
    return (data.tilesets and data.tilesets[def.tileset])
      or (data.gen2Tilesets and data.gen2Tilesets[def.tileset]) or nil
  end

  local function pretty(base)
    return tostring(base or "KANTO"):gsub("POKEMON_", "PKMN ")
      :gsub("MT_MOON", "MT MOON"):gsub("MOUNT_MOON", "MT MOON")
      :gsub("CERULEAN_CAVE", "CERULEAN CAVE")
      :gsub("SEAFOAM_ISLANDS", "SEAFOAM")
      :gsub("SILVER_CAVE", "MT SILVER")
      :gsub("VICTORY_ROAD", "VICTORY ROAD"):gsub("_", " ")
  end

  local function setOf(rows)
    local out = {}
    for key, value in pairs(rows or {}) do
      if type(key) == "number" and type(value) == "number" then
        out[value] = true
      elseif value == true then
        out[key] = true
      end
    end
    return out
  end

  local function tileAt(def, tileset, x, y)
    if not (def and tileset and def.blocks and tileset.blocks) then return nil end
    if x < 0 or y < 0 or x >= def.width * 2 or y >= def.height * 2 then return nil end
    local block = def.blocks[math.floor(y / 2) * def.width + math.floor(x / 2) + 1]
    local graphic = tileset.blocks[(block or 0) + 1]
    if not graphic then return nil end
    return graphic[5 + (x % 2) * 2 + (y % 2) * 8]
  end

  local function candidates(base, includeBorder)
    local def = sourceMap(base)
    local tileset = sourceTileset(def)
    if not (def and tileset and def.width and def.height) then return {} end
    local walkable, occupied, hazards = setOf(tileset.walkable), {}, {}
    local function key(x, y) return tostring(x) .. ":" .. tostring(y) end
    for _, obj in ipairs(def.objects or {}) do
      occupied[key(obj.x, obj.y)] = true
    end
    for _, warp in ipairs(def.warps or {}) do
      occupied[key(warp.x, warp.y)] = true
      hazards[#hazards + 1] = { x=warp.x, y=warp.y, radius=1 }
    end
    for _, sign in ipairs(def.signs or {}) do
      occupied[key(sign.x, sign.y)] = true
    end
    local function passable(x, y)
      -- Gen II tilesets carry COLL_* quads rather than Gen I walkable tile
      -- lists. The shared Map facade answers the same cell-level question for
      -- R/B/Y and G/S/C without comparing values from the two number spaces.
      if okMapModel and MapModel
          and type(MapModel.defIsWalkableCell)=="function" then
        return MapModel.defIsWalkableCell(def,tileset,x,y)
      end
      local tile = tileAt(def, tileset, x, y)
      return tile ~= nil and walkable[tile] == true
    end
    local out = {}
    local minCoord=includeBorder and 0 or 1
    local maxX=def.width*2-1-(includeBorder and 0 or 1)
    local maxY=def.height*2-1-(includeBorder and 0 or 1)
    for y=minCoord,maxY do
      for x=minCoord,maxX do
        if passable(x, y) and not occupied[key(x, y)] then
          local clear = true
          for _, hazard in ipairs(hazards) do
            if math.abs(x-hazard.x)+math.abs(y-hazard.y) <= hazard.radius then
              clear = false
              break
            end
          end
          if clear then
            local east,west=passable(x+1,y),passable(x-1,y)
            local south,north=passable(x,y+1),passable(x,y-1)
            local degree = 0
            if east then degree=degree+1 end
            if west then degree=degree+1 end
            if south then degree=degree+1 end
            if north then degree=degree+1 end
            if degree > 0 then
              -- A two-sided turn is safe for an NPC when its inside diagonal
              -- is also walkable, since the player can step around the corner.
              local cornerSafe=degree==2 and (
                (east and south and passable(x+1,y+1)) or
                (east and north and passable(x+1,y-1)) or
                (west and south and passable(x-1,y+1)) or
                (west and north and passable(x-1,y-1)))
              out[#out+1] = {x=x,y=y,degree=degree,
                cornerSafe=cornerSafe,
                edge=math.min(x,y,def.width*2-1-x,def.height*2-1-y)}
            end
          end
        end
      end
    end
    table.sort(out, function(a,b)
      if a.degree ~= b.degree then return a.degree < b.degree end
      if a.edge ~= b.edge then return a.edge < b.edge end
      if a.y ~= b.y then return a.y < b.y end
      return a.x < b.x
    end)
    return out
  end

  local reserved = {}
  local usedByMap = {}
  local function farFromUsed(base, row, distance)
    for _, used in ipairs(usedByMap[base] or {}) do
      if math.abs(row.x-used.x)+math.abs(row.y-used.y) < distance then return false end
    end
    return true
  end

  local function slotsFor(mapNames, wanted, perMap, minimumDegree, allowCorners)
    if wanted <= 0 then return {} end
    local choices, selected, counts = {}, {}, {}
    for _, base in ipairs(mapNames) do
      local rows=candidates(base)
      if minimumDegree then
        local open={}
        for _,row in ipairs(rows) do
          if row.degree>=minimumDegree or (allowCorners and row.cornerSafe) then
            open[#open+1]=row
          end
        end
        rows=open
      end
      choices[base]=rows
    end
    local maximum = perMap or 12
    -- Prefer widely separated dead ends first, then progressively admit
    -- ordinary path tiles and closer spacing. A sparse map no longer prevents
    -- another Kanto map from supplying the remaining placements.
    for _, distance in ipairs({5,3,2,1}) do
      local progress = true
      while progress and #selected < wanted do
        progress = false
        for _, base in ipairs(mapNames) do
          if (counts[base] or 0) < maximum then
            local rows, pick = choices[base] or {}, nil
            for _, row in ipairs(rows) do
              local key = base..":"..row.x..":"..row.y
              if not reserved[key] and farFromUsed(base,row,distance) then
                pick=row
                break
              end
            end
            if pick then
              selected[#selected+1] = {base=base,x=pick.x,y=pick.y}
              reserved[base..":"..pick.x..":"..pick.y] = true
              counts[base]=(counts[base] or 0)+1
              usedByMap[base] = usedByMap[base] or {}
              usedByMap[base][#usedByMap[base]+1] = pick
              progress = true
              if #selected >= wanted then return selected end
            end
          end
        end
      end
    end
    -- The normal cap is about visual distribution, not validity. If a
    -- cartridge exposes fewer usable Kanto maps than expected, use additional
    -- distinct tiles in the maps that did resolve instead of aborting the
    -- entire content mod and reverting the Pokédex to the cartridge roster.
    local progress = true
    while progress and #selected < wanted do
      progress = false
      for _, base in ipairs(mapNames) do
        local rows, pick = choices[base] or {}, nil
        for _, row in ipairs(rows) do
          local key = base..":"..row.x..":"..row.y
          if not reserved[key] then pick=row break end
        end
        if pick then
          selected[#selected+1] = {base=base,x=pick.x,y=pick.y}
          reserved[base..":"..pick.x..":"..pick.y] = true
          usedByMap[base] = usedByMap[base] or {}
          usedByMap[base][#usedByMap[base]+1] = pick
          progress = true
          if #selected >= wanted then return selected end
        end
      end
    end
    error(("not enough native placements: wanted %d, found %d")
      :format(wanted,#selected),0)
  end

  -- Keep the requested lab-aide and monster overworld art without retaining
  -- any imported map, tileset, trainer, or script registry.
  for _, sprite in ipairs({"KJT_SPRITE_SCIENTIST","KJT_SPRITE_MONSTER"}) do
    if not mod.content.sprites:get(sprite) then
      mod.content.sprites:register(sprite,assert(sprites[sprite],"missing sprite "..sprite))
    end
  end

  local function appendMapObject(base, object)
    local patch = {objects={__append={object}}}
    -- The Gen 2 save editor applies mod patches without first hydrating its native
    -- map record. Carry the native descriptor so the patched map remains
    -- previewable there; gameplay still inherits cartridge warps and scripts.
    if not gen1 then
      local def = assert(sourceMap(base),"missing native map "..base)
      patch.id=base; patch.label=def.label or base; patch.tileset=def.tileset
      patch.width=def.width; patch.height=def.height; patch.blocks=def.blocks
      patch.borderBlock=def.borderBlock; patch.region=def.region
    end
    mod.content.maps:patch(base,patch)
  end

  -- Gen II currently loads map object patches but deliberately gates the Gen I
  -- map_scripts registry. Bridge conversations attached to objects created by
  -- this mod through the cross-generation world.interacted event. R/B/Y keeps
  -- using the engine's complete script runner unchanged.
  local registerTalk
  do
    local gen2TalkByCell={}
    local gen2TalkActive=false

    local function stateKey(key)
      local value=tostring(key or "")
      return value:sub(1,4)=="mod:" and value:sub(5) or value
    end

    local function getModField(key)
      return mod.save:get(stateKey(key),false)==true
    end

    local function setModField(key,value)
      mod.save:set(stateKey(key),value==true)
    end

    local function hasBadge(save,badge)
      save=save or {}
      local player=save.player or {}
      local inventory=save.inventory or {}
      local held=inventory[badge]
      -- Gen I item constants include BADGE; Gen II's player badge sets use
      -- BOULDER/CASCADE/... and RISING-style keys.
      local engineBadge=tostring(badge or ""):gsub("BADGE$","")
      return held==true or (tonumber(held) or 0)>0
        or (type(player.badges)=="table"
          and (not not player.badges[badge] or not not player.badges[engineBadge]))
        or (type(player.kantoBadges)=="table"
          and (not not player.kantoBadges[badge]
            or not not player.kantoBadges[engineBadge]))
    end

    local function hasRegigigasKeys(save)
      local found={}
      for _,mon in ipairs((save and save.party) or {}) do
        if mon and mon.species then found[mon.species]=true end
      end
      return found.REGIROCK and found.REGICE and found.REGISTEEL or false
    end

    local function giveGen2Pokemon(species,level)
      local game=mod.world and mod.world.game
      local save=game and game.save
      if not (game and game.data and save) then return false end
      local okMon,Mon=pcall(require,"src.battle.gen2.Mon")
      local okParty,Party=pcall(require,"src.pokemon.Party")
      if not (okMon and Mon and okParty and Party) then return false end
      local mon=Mon.new(game.data,species,level or 5)
      if not mon then return false end
      save.party=save.party or {}
      Mon.stampOT(save,mon)
      if not Party.add(save.party,mon) then return false end
      save.pokedex=save.pokedex or {}
      save.pokedex.seen=save.pokedex.seen or {}
      save.pokedex.caught=save.pokedex.caught or {}
      save.pokedex.owned=save.pokedex.owned or {}
      save.pokedex.seen[species]=true
      save.pokedex.caught[species]=true
      save.pokedex.owned[species]=true
      return true
    end

    local function warnTalk(message)
      if mod.log and mod.log.warn then
        mod.log:warn("Crystal aide conversation: %s",tostring(message))
      end
    end

    local function runGen2Talk(entry)
      local rows=entry.rows
      local labels={}
      for index,row in ipairs(rows) do
        if type(row)=="table" and row[1]=="label" then labels[row[2]]=index end
      end
      local pc,lastCheck=1,false
      local function finish()
        gen2TalkActive=false
      end
      local step
      step=function()
        while true do
          local row=rows[pc]
          if not row then finish() return end
          pc=pc+1
          local command=row[1]
          if command=="label" or command=="face_player" then
            -- Labels are bookkeeping. The NPC is faced before execution.
          elseif command=="check_flag" then
            lastCheck=getModField(row[2])
          elseif command=="set_field" then
            setModField(row[2],row[3])
          elseif command=="check_item" or command=="knd_has_badge" then
            local game=mod.world and mod.world.game
            lastCheck=hasBadge(game and game.save,row[2])
          elseif command=="knd_has_regigigas_keys" then
            local game=mod.world and mod.world.game
            lastCheck=hasRegigigasKeys(game and game.save)
          elseif command=="give_pokemon" then
            lastCheck=giveGen2Pokemon(row[2],row[3])
          elseif command=="jump_if_true" or command=="jump_if_false" then
            local take=(command=="jump_if_true" and lastCheck)
              or (command=="jump_if_false" and not lastCheck)
            if take then
              local destination=labels[row[2]]
              if not destination then finish() return end
              pc=destination+1
            end
          elseif command=="jump" then
            local destination=labels[row[2]]
            if not destination then finish() return end
            pc=destination+1
          elseif command=="show_text" then
            local ok,err=mod.world:queueScript({{"text",row[2]}},{
              onDone=function(success)
                if success then step() else finish() end
              end,
            })
            if not ok then warnTalk(err) finish() end
            return
          elseif command=="warp" then
            local ok,err=mod.world:queueScript({
              {"warp",row[2],row[3],row[4],row[5]},
            },{onDone=function() finish() end})
            if not ok then warnTalk(err) finish() end
            return
          else
            warnTalk("unsupported command "..tostring(command))
            finish()
            return
          end
        end
      end

      local current=mod.world and mod.world:current()
      if current and entry.objectName then
        local npc=mod.world:npc(entry.mapId,entry.objectName)
        local opposite={up="down",down="up",left="right",right="left"}
        if npc and opposite[current.facing] then npc:face(opposite[current.facing]) end
      end
      step()
    end

    registerTalk=function(base,textId,x,y,rows,objectName)
      if gen1 then
        mod.content.map_scripts:register(base,{talk={[textId]=rows}})
        return
      end
      gen2TalkByCell[base..":"..tostring(x)..":"..tostring(y)]={
        mapId=base,rows=rows,objectName=objectName,
      }
    end

    if not gen1 then
      mod.events:on("world.interacted",function(event)
        if gen2TalkActive or not (event and mod.world) then return end
        if event.kind~="none" and event.kind~="npc" then return end
        local entry=gen2TalkByCell[tostring(event.mapId)..":"
          ..tostring(event.x)..":"..tostring(event.y)]
        if not entry then return end
        gen2TalkActive=true
        runGen2Talk(entry)
      end)
    end
  end

  local REGIGIGAS_CHAMBER="KND_REGIGIGAS_CHAMBER"
  local REGIGIGAS_CHAMBER_LABEL="KNDRegigigasChamber"

  -- The chamber gate follows Platinum's rule: all three golems must be in
  -- the active party. A script command keeps this check portable across the
  -- Gen I and Gen II map interpreters.
  mod.commands:register("knd_has_regigigas_keys",function(ctx)
    local found={}
    for _,mon in ipairs((ctx.save and ctx.save.party) or {}) do
      if mon and mon.species then found[mon.species]=true end
    end
    ctx.lastCheck=found.REGIROCK and found.REGICE and found.REGISTEEL or false
  end)

  -- Native encounters and mod-scripted encounters both update the Pokédex.
  -- Reading both cartridge spellings lets a later family stage depend on a
  -- capture without replacing the native encounter that supplied it.
  mod.commands:register("knd_has_caught_all",function(ctx,...)
    local dex=ctx.save and ctx.save.pokedex or {}
    local owned=type(dex.owned)=="table" and dex.owned or {}
    local caught=type(dex.caught)=="table" and dex.caught or {}
    local all=true
    for _,species in ipairs({...}) do
      if not owned[species] and not caught[species] then all=false break end
    end
    ctx.lastCheck=all
  end)

  -- R/B/Y represents badges as key items, while G/S/C keeps Johto and Kanto
  -- badge sets on the player record.  Quest scripts call this command so a
  -- generation-specific profile can use either representation safely.
  mod.commands:register("knd_has_badge",function(ctx,badge)
    local save=ctx.save or {}
    local player=save.player or {}
    local inventory=save.inventory or {}
    local held=inventory[badge]
    ctx.lastCheck=held==true or (tonumber(held) or 0)>0
      or (type(player.badges)=="table" and not not player.badges[badge])
      or (type(player.kantoBadges)=="table" and not not player.kantoBadges[badge])
  end)

  local function safeNeighbor(base,x,y)
    local usable={}
    for _,row in ipairs(candidates(base)) do
      usable[tostring(row.x)..":"..tostring(row.y)]=true
    end
    local rows={
      {x=x,y=y+1,facing="up"},{x=x,y=y-1,facing="down"},
      {x=x+1,y=y,facing="left"},{x=x-1,y=y,facing="right"},
    }
    for _,row in ipairs(rows) do
      if usable[tostring(row.x)..":"..tostring(row.y)] then return row end
    end
    -- Authored entrance tiles are already required to be reachable. This is
    -- only a fallback for an unusually restrictive source-map descriptor.
    return rows[1]
  end

  local function registerRegigigasChamber(entranceMap,entranceX,entranceY,level)
    local source=assert(sourceMap(entranceMap),
      "missing Regigigas chamber source map "..entranceMap)
    local tileset=assert(sourceTileset(source),
      "missing Regigigas chamber source tileset")
    local tilesetId=source.tileset
    if type(tilesetId)~="string" then
      tilesetId="KND_REGIGIGAS_CHAMBER_TILESET"
    end
    if not mod.content.tilesets:get(tilesetId) then
      mod.content.tilesets:register(tilesetId,tileset)
    end

    local walkable=setOf(tileset.walkable)
    local function quadrantCount(blockId)
      if okMapModel and MapModel
          and type(MapModel.defIsWalkableCell)=="function" then
        local probe={width=1,height=1,blocks={blockId},borderBlock=blockId}
        local count=0
        for y=0,1 do
          for x=0,1 do
            if MapModel.defIsWalkableCell(probe,tileset,x,y) then
              count=count+1
            end
          end
        end
        return count
      end
      local graphic=tileset.blocks and tileset.blocks[(blockId or 0)+1]
      if not graphic then return -1 end
      local count=0
      for _,position in ipairs({5,7,13,15}) do
        if walkable[graphic[position]] then count=count+1 end
      end
      return count
    end
    local frequency={}
    for _,blockId in ipairs(source.blocks or {}) do
      frequency[blockId]=(frequency[blockId] or 0)+1
    end
    local floorBlock,floorFrequency=nil,-1
    for blockId,count in pairs(frequency) do
      if quadrantCount(blockId)==4 and count>floorFrequency then
        floorBlock,floorFrequency=blockId,count
      end
    end
    if floorBlock==nil then
      for index in ipairs(tileset.blocks or {}) do
        if quadrantCount(index-1)==4 then floorBlock=index-1 break end
      end
    end
    assert(floorBlock~=nil,"Regigigas chamber tileset has no walkable block")

    local wallBlock=source.borderBlock
    if quadrantCount(wallBlock)>0 then wallBlock=nil end
    if wallBlock==nil then
      for index in ipairs(tileset.blocks or {}) do
        if quadrantCount(index-1)==0 then wallBlock=index-1 break end
      end
    end
    assert(wallBlock~=nil,"Regigigas chamber tileset has no solid block")

    local width,height=7,7
    local chamberBlocks={}
    for blockY=1,height do
      for blockX=1,width do
        local edge=blockX==1 or blockX==width or blockY==1 or blockY==height
        chamberBlocks[#chamberBlocks+1]=edge and wallBlock or floorBlock
      end
    end

    local encounterText="_KJT_STATIC_REGIGIGAS"
    local returnText="TEXT_KND_REGIGIGAS_CHAMBER_RETURN"
    mod.content.text:register(encounterText,
      "REGIGIGAS is watching you.\nAccept its challenge?")
    mod.content.text_pointers:register(REGIGIGAS_CHAMBER_LABEL,{
      [encounterText]={text=encounterText},
    })
    mod.content.maps:register(REGIGIGAS_CHAMBER,{
      id=REGIGIGAS_CHAMBER,label=REGIGIGAS_CHAMBER_LABEL,index=2300,
      tileset=tilesetId,width=width,height=height,blocks=chamberBlocks,
      borderBlock=wallBlock,region=source.region or "kanto",
      warps={},signs={},connections={},objects={
        {index=1,name="KND_REGIGIGAS_CHAMBER_STATIC",pokemon="REGIGIGAS",
          level=level,movement="STAY",range="ANY_DIR",
          sprite="KJT_SPRITE_MONSTER",text=encounterText,x=7,y=4},
        {index=2,name="KND_REGIGIGAS_CHAMBER_RETURN",movement="STAY",
          range="ANY_DIR",sprite="KJT_SPRITE_SCIENTIST",text=returnText,
          x=7,y=11},
      },
    })
    mod.content.map_songs:register(REGIGIGAS_CHAMBER,"Music_Dungeon3")

    local returnTo=safeNeighbor(entranceMap,entranceX,entranceY)
    registerTalk(REGIGIGAS_CHAMBER,returnText,7,11,
      {{"face_player"},
        {"show_text","I'll lead you back\nto VICTORY ROAD."},
        {"warp",entranceMap,returnTo.x,returnTo.y,returnTo.facing}},
      "KND_REGIGIGAS_CHAMBER_RETURN")

    local gateText="TEXT_KND_REGIGIGAS_CHAMBER_GATE"
    appendMapObject(entranceMap,{
      index=1486,name=entranceMap.."_KND_REGIGIGAS_GATE",
      movement="STAY",range="ANY_DIR",sprite="KJT_SPRITE_SCIENTIST",
      text=gateText,x=entranceX,y=entranceY,
    })
    registerTalk(entranceMap,gateText,entranceX,entranceY,
      {{"face_player"},
        {"show_text",researchProfessor.." asked me\nto investigate a\fmysterious carving\non this wall.\fIt speaks of a\nunion between\nSTEEL, ICE, and\nROCK."},
        {"knd_has_regigigas_keys"},
        {"jump_if_false","locked"},
        {"show_text","Your three POKéMON\nmade the carving\nreact!\fThe wall is moving!"},
        {"warp",REGIGIGAS_CHAMBER,7,10,"up"},{"jump","end"},
        {"label","locked"},
        {"show_text","The carving hasn't\nreacted."}},
      entranceMap.."_KND_REGIGIGAS_GATE")
  end

  local starterMaps = {
    "PEWTER_CITY","CERULEAN_CITY","VERMILION_CITY","LAVENDER_TOWN",
    "CELADON_CITY","FUCHSIA_CITY","SAFFRON_CITY","CINNABAR_ISLAND",
    "VIRIDIAN_CITY","PALLET_TOWN","ROUTE_2","ROUTE_3","ROUTE_4",
    "ROUTE_5","ROUTE_6","ROUTE_7","ROUTE_8","ROUTE_9","ROUTE_10_NORTH",
    "ROUTE_11","ROUTE_13","ROUTE_14","ROUTE_15","ROUTE_16",
    "ROUTE_18","ROUTE_24","ROUTE_25",
  }
  local gen2StarterMaps = {
    "NEW_BARK_TOWN","CHERRYGROVE_CITY","VIOLET_CITY","GOLDENROD_CITY",
    "ECRUTEAK_CITY","OLIVINE_CITY","CIANWOOD_CITY","MAHOGANY_TOWN",
    "BLACKTHORN_CITY","NATIONAL_PARK","ILEX_FOREST","LAKE_OF_RAGE",
    "ROUTE_29","ROUTE_30","ROUTE_31","ROUTE_32","ROUTE_33","ROUTE_34",
    "ROUTE_35","ROUTE_36","ROUTE_37","ROUTE_38","ROUTE_39","ROUTE_40",
    "ROUTE_41","ROUTE_42","ROUTE_43","ROUTE_44","ROUTE_45","ROUTE_46",
  }
  -- Crystal shares the Gen II registry: its native Johto names must seed the
  -- allocator before authored Kanto coordinates are considered individually.
  if not gen1 then
    for _,base in ipairs(starterMaps) do
      gen2StarterMaps[#gen2StarterMaps+1]=base
    end
  end
  local starterSlots = slotsFor(gen1 and starterMaps or gen2StarterMaps,27,2)
  local starterCoordinates = {
    SPRIGATITO = { x = 13, y = 11 },
    QUAXLY = { base = "PEWTER_CITY", x = 34, y = 2 },
    FROAKIE = { base = "ROUTE_9", x = 3, y = 9 },
    CYNDAQUIL = { base = "CELADON_CITY", x = 46, y = 24 },
    SOBBLE = { base = "ROUTE_18", x = 35, y = 16 },
    OSHAWOTT = { base = "SAFFRON_CITY", x = 23, y = 34 },
    MUDKIP = { base = "VIRIDIAN_CITY", x = 35, y = 2 },
    CHIMCHAR = { base = "ROUTE_2", x = 12, y = 44 },
    TEPIG = { base = "ROUTE_5", x = 17, y = 32 },
    ROWLET = { base = "ROUTE_10_NORTH", x = 2, y = 29 },
    LITTEN = { base = "ROUTE_11", x = 9, y = 0 },
    POPPLIO = { base = "ROUTE_13", x = 36, y = 3 },
    GROOKEY = { base = "ROUTE_15", x = 15, y = 4 },
    SCORBUNNY = { base = "ROUTE_15", x = 15, y = 13 },
  }
  local badgeNames = {
    BOULDERBADGE="BOULDER BADGE",CASCADEBADGE="CASCADE BADGE",
    THUNDERBADGE="THUNDER BADGE",RAINBOWBADGE="RAINBOW BADGE",
    SOULBADGE="SOUL BADGE",MARSHBADGE="MARSH BADGE",
    VOLCANOBADGE="VOLCANO BADGE",EARTHBADGE="EARTH BADGE",
  }
  for badge,name in pairs((gen2Profile and gen2Profile.badgeNames) or {}) do
    badgeNames[badge]=name
  end
  local researchRegion=(gen2Profile and gen2Profile.region) or "kanto"
  local researchPrefix=(gen2Profile and gen2Profile.regionPrefix) or "K: "
  local gen2QuestResearchers=(gen2Profile and gen2Profile.researchers) or {}
  local gen2KantoMaps={
    MOUNT_MOON=true,ROCK_TUNNEL_1F=true,ROCK_TUNNEL_B1F=true,
    POWER_PLANT=true,DIGLETTS_CAVE=true,ROUTE_23=true,ROUTE_24=true,
    ROUTE_25=true,
  }
  for _,base in ipairs(starterMaps) do gen2KantoMaps[base]=true end
  local function mapRegion(mapId)
    if gen1 or gen2KantoMaps[mapId] then return "kanto","K: " end
    return "johto","J: "
  end
  local function questDefinition(key,kantoMap,kantoBadge)
    local override=gen2QuestResearchers[key]
    return (override and override.map) or kantoMap,
      (override and override.badge) or kantoBadge
  end
  local hiddenKantoStarters={BULBASAUR=true,CHARMANDER=true,SQUIRTLE=true}
  local normalizedVersion=tostring(gameVersion or "unknown"):lower()
  local hideKantoStarterAides=gen1
    and normalizedVersion:find("yellow",1,true)~=nil
  local placements, starterNumber, visibleStarterGifts = {
    starters={},statics={},quests={},hiddenStarterGifts={},
    adjustedStarterCoordinates={}},0,0
  for _, group in ipairs(catalog.starterGroups or {}) do
    for _, species in ipairs(group.species or {}) do
      starterNumber=starterNumber+1
      local slot,badge=starterSlots[starterNumber],group.badge
      local authored=starterCoordinates[species]
      if authored then
        local oldKey=slot.base..":"..slot.x..":"..slot.y
        local authoredBase=authored.base or slot.base
        local selected,bestDistance=nil,nil
        for _,row in ipairs(candidates(authoredBase,true)) do
          local candidateKey=authoredBase..":"..row.x..":"..row.y
          if not reserved[candidateKey] or candidateKey==oldKey then
            local distance=math.abs(row.x-authored.x)+math.abs(row.y-authored.y)
            if bestDistance==nil or distance<bestDistance
                or (distance==bestDistance and (row.y<selected.y
                  or (row.y==selected.y and row.x<selected.x))) then
              selected={x=row.x,y=row.y}
              bestDistance=distance
            end
          end
        end
        if not selected then
          placements.adjustedStarterCoordinates[species]={
            map=slot.base,requestedMap=authoredBase,
            requestedX=authored.x,requestedY=authored.y,
            x=slot.x,y=slot.y,game=normalizedVersion,
            reason="authored map has no usable tiles",
          }
          if mod.log and mod.log.warn then
            mod.log:warn("%s authored map %s is unusable in %s; retaining safe slot %s %d,%d",
              species,authoredBase,normalizedVersion,slot.base,slot.x,slot.y)
          end
        else
          local newKey=authoredBase..":"..selected.x..":"..selected.y
          if selected.x~=authored.x or selected.y~=authored.y then
            placements.adjustedStarterCoordinates[species]={
              map=authoredBase,requestedMap=authoredBase,
              requestedX=authored.x,requestedY=authored.y,
              x=selected.x,y=selected.y,game=normalizedVersion,
              reason="requested tile is not usable",
            }
            if mod.log and mod.log.warn then
              mod.log:warn("%s starter tile %d,%d is unusable in %s; using %d,%d",
                species,authored.x,authored.y,normalizedVersion,selected.x,selected.y)
            end
          end
          reserved[oldKey]=nil
          reserved[newKey]=true
          local oldUsed=usedByMap[slot.base] or {}
          for usedIndex,used in ipairs(oldUsed) do
            if used.x==slot.x and used.y==slot.y then
              if authoredBase==slot.base then
                used.x,used.y=selected.x,selected.y
              else
                table.remove(oldUsed,usedIndex)
                usedByMap[authoredBase]=usedByMap[authoredBase] or {}
                usedByMap[authoredBase][#usedByMap[authoredBase]+1]={
                  x=selected.x,y=selected.y,
                }
              end
              break
            end
          end
          slot={base=authoredBase,x=selected.x,y=selected.y}
        end
      end
      if hideKantoStarterAides and hiddenKantoStarters[species] then
        placements.hiddenStarterGifts[species]={game=normalizedVersion,
          reason="native yellow gift"}
      else
        visibleStarterGifts=visibleStarterGifts+1
        local mapId,textId,flag=slot.base,"TEXT_KJT_GIFT_"..species,
          "mod:kjt_starter_"..species
        appendMapObject(mapId,{
          index=600+starterNumber,name=mapId.."_KJT_GIFT_"..species,
          movement="STAY",range="ANY_DIR",sprite="KJT_SPRITE_SCIENTIST",
          text=textId,x=slot.x,y=slot.y,
        })
        registerTalk(mapId,textId,slot.x,slot.y,{
          {"face_player"},{"check_flag",flag},{"jump_if_true","owned"},
          {"show_text","PROF.OAK asked me\nto look for you!\fIf you have the\n"..badgeNames[badge]..",\fI am supposed to\ngive you a\n"..species:gsub("_"," ").."."},
          {"check_item",badge},{"jump_if_false","locked"},
          {"show_text","Great! You have\nthe "..badgeNames[badge].."!\fHere you go!"},
          {"give_pokemon",species,5},{"jump_if_false","full"},{"set_field",flag,true},
          {"show_text",species:gsub("_"," ").." joined you!"},{"jump","end"},
          {"label","owned"},{"show_text","Take good care of\nyour new partner."},{"jump","end"},
          {"label","locked"},{"show_text","You don't have the\n"..badgeNames[badge].." yet.\fPlease come back\nwhen you do."},{"jump","end"},
          {"label","full"},{"show_text","Your party and PC\nBOXES are full.\nPlease make room."},
        },mapId.."_KJT_GIFT_"..species)
        local starterRegion,starterPrefix=mapRegion(mapId)
        placements.starters[species]={map=mapId,nativeMap=mapId,
          label=starterPrefix..pretty(mapId),region=starterRegion,
          x=slot.x,y=slot.y,badge=badge}
      end
    end
  end

  local gen1Maps = {
    "MT_MOON_1F","MT_MOON_B1F","MT_MOON_B2F","ROCK_TUNNEL_1F",
    "ROCK_TUNNEL_B1F","POKEMON_TOWER_3F","POKEMON_TOWER_4F",
    "POKEMON_TOWER_5F","POKEMON_TOWER_6F","POKEMON_TOWER_7F",
    "SILPH_CO_5F","SILPH_CO_7F","SILPH_CO_9F","POWER_PLANT",
    "SEAFOAM_ISLANDS_B1F","SEAFOAM_ISLANDS_B2F","SEAFOAM_ISLANDS_B3F",
    "SEAFOAM_ISLANDS_B4F","POKEMON_MANSION_1F","POKEMON_MANSION_2F",
    "POKEMON_MANSION_3F","POKEMON_MANSION_B1F","VICTORY_ROAD_1F",
    "VICTORY_ROAD_2F","VICTORY_ROAD_3F","CERULEAN_CAVE_1F",
    "CERULEAN_CAVE_2F","CERULEAN_CAVE_B1F",
  }
  local gen2Maps = {
    "MOUNT_MOON","ROCK_TUNNEL_1F","ROCK_TUNNEL_B1F","POWER_PLANT",
    "DIGLETTS_CAVE","TOHJO_FALLS","VICTORY_ROAD","ROUTE_23",
    "ROUTE_24","ROUTE_25","SILVER_CAVE_OUTSIDE","SILVER_CAVE_ROOM_1",
    "SILVER_CAVE_ROOM_2","SILVER_CAVE_ROOM_3","SILVER_CAVE_ITEM_ROOMS",
  }
  local staticMaps=gen1 and gen1Maps or gen2Maps
  local native={}
  for _,species in ipairs((gen1 and catalog.nativeStatics or catalog.gen2NativeStatics) or {}) do
    native[species]=true
  end
  local addedRows={}
  for _,spot in ipairs(catalog.staticSpecies or {}) do
    if not native[spot.species] then addedRows[#addedRows+1]=spot end
  end
  local staticSlots=slotsFor(staticMaps,#addedRows,12)
  -- Small authored corrections applied after the deterministic allocator.
  -- These are map-tile deltas, not image offsets, so the object, encounter,
  -- and exported Pokédex AREA coordinates all continue to agree.
  local staticNudges={
    TYPE_NULL={x=-1,y=-3},
  }
  local staticCoordinates={
    CRESSELIA={x=16,y=0},
    TAPU_LELE={x=23,y=0},
  }
  local gen1StaticOverrides={
    REGIGIGAS={base="VICTORY_ROAD_2F",x=9,y=13},
  }

  -- Family quest state is deliberately kept in mod-owned save flags.  The
  -- encounter scripts only consume portable commands shared by the R/B/Y and
  -- G/S interpreters, and a battle without a capture leaves the quest open.
  local questFlags={
    birdsStarted="mod:knd_quest_birds_started",
    articunoOpen="mod:knd_quest_articuno_open",
    zapdosOpen="mod:knd_quest_zapdos_open",
    moltresOpen="mod:knd_quest_moltres_open",
    regisStarted="mod:knd_quest_regis_started",
    regirockOpen="mod:knd_quest_regirock_open",
    regiceOpen="mod:knd_quest_regice_open",
    registeelOpen="mod:knd_quest_registeel_open",
    regielekiOpen="mod:knd_quest_regieleki_open",
    regidragoOpen="mod:knd_quest_regidrago_open",
    lunarStarted="mod:knd_quest_lunar_started",
    cresseliaOpen="mod:knd_quest_cresselia_open",
    darkraiOpen="mod:knd_quest_darkrai_open",
  }
  local function completedFlag(species)
    return "mod:knd_quest_completed_"..species
  end
  local function battleFlag(species)
    return "mod:knd_quest_battle_"..species
  end
  local questStatics={
    ARTICUNO={family="birds",unlock=questFlags.articunoOpen},
    ZAPDOS={family="birds",unlock=questFlags.zapdosOpen},
    MOLTRES={family="birds",unlock=questFlags.moltresOpen},
    REGIROCK={family="regis",unlock=questFlags.regirockOpen,
      nextUnlock={questFlags.regiceOpen}},
    REGICE={family="regis",unlock=questFlags.regiceOpen,
      nextUnlock={questFlags.registeelOpen}},
    REGISTEEL={family="regis",unlock=questFlags.registeelOpen,
      nextUnlock={questFlags.regielekiOpen,questFlags.regidragoOpen}},
    REGIELEKI={family="regis",unlock=questFlags.regielekiOpen},
    REGIDRAGO={family="regis",unlock=questFlags.regidragoOpen},
    CRESSELIA={family="lunar",unlock=questFlags.cresseliaOpen,
      nextUnlock={questFlags.darkraiOpen}},
    DARKRAI={family="lunar",unlock=questFlags.darkraiOpen},
  }

  local genericQuestFlags={}
  for _,family in ipairs(catalog.familyQuests or {}) do
    local started="mod:knd_quest_"..family.id:lower().."_started"
    genericQuestFlags[family.id]=started
    local prior={}
    for _,stage in ipairs(family.stages or {}) do
      for _,species in ipairs(stage) do
        if not questStatics[species] then
          local requirements={}
          for _,required in ipairs(prior) do requirements[#requirements+1]=required end
          questStatics[species]={family=family.id:lower(),unlock=started,
            requiresCaught=requirements}
          -- R/B/Y's native Mewtwo remains completely untouched. Catching it
          -- is itself sufficient to awaken Mew at Mew's existing placement;
          -- no prior researcher conversation is required on that cartridge.
          if species=="MEW" then questStatics[species].unlock=nil end
        end
      end
      for _,species in ipairs(stage) do prior[#prior+1]=species end
    end
  end

  local function registerQuestStatic(mapId,spot,level,textId,objectName,quest)
    appendMapObject(mapId,{
      index=1000+spot.dex,name=objectName,movement="STAY",range="ANY_DIR",
      sprite="KJT_SPRITE_MONSTER",text=textId,x=spot.x,y=spot.y,
    })
    local rows={
      {"check_flag",completedFlag(spot.species)},{"jump_if_true","gone"},
    }
    if quest.unlock then
      rows[#rows+1]={"check_flag",quest.unlock}
      rows[#rows+1]={"jump_if_false","locked"}
    end
    if #(quest.requiresCaught or {})>0 then
      local check={"knd_has_caught_all"}
      for _,species in ipairs(quest.requiresCaught) do check[#check+1]=species end
      rows[#rows+1]=check
      rows[#rows+1]={"jump_if_false","prerequisite"}
    end
    rows[#rows+1]={"face_player"}
    rows[#rows+1]={"ask",spot.species:gsub("_"," ").." is watching you.\nAccept its challenge?"}
    rows[#rows+1]={"jump_if_false","end"}
    rows[#rows+1]={"play_cry",spot.species}
    rows[#rows+1]={"static_battle",spot.species,level,battleFlag(spot.species)}
    rows[#rows+1]={"check_battle_result","caught"}
    rows[#rows+1]={"jump_if_false","end"}
    rows[#rows+1]={"set_field",completedFlag(spot.species),true}
    for _,flag in ipairs(quest.nextUnlock or {}) do
      rows[#rows+1]={"set_field",flag,true}
    end
    rows[#rows+1]={"hide_object",mapId,objectName}
    rows[#rows+1]={"show_text","The encounter was recorded in "..researchProfessor.."'S research notes."}
    rows[#rows+1]={"jump","end"}
    rows[#rows+1]={"label","locked"}
    rows[#rows+1]={"show_text","The air feels unusual, but nothing answers.\nAn investigator may know more."}
    rows[#rows+1]={"jump","end"}
    if #(quest.requiresCaught or {})>0 then
      rows[#rows+1]={"label","prerequisite"}
      rows[#rows+1]={"show_text","The legendary presence is still dormant.\nComplete the earlier parts of this family mystery first."}
      rows[#rows+1]={"jump","end"}
    end
    rows[#rows+1]={"label","gone"}
    rows[#rows+1]={"show_text","Only traces of the legendary POKEMON remain."}
    mod.content.map_scripts:register(mapId,{talk={[textId]=rows}})
  end

  local staticCount=0
  for index,spot in ipairs(addedRows) do
    local allocated=staticSlots[index]
    local nudge=staticNudges[spot.species]
    local slot=nudge and {base=allocated.base,
      x=allocated.x+nudge.x,y=allocated.y+nudge.y} or allocated
    local coordinates=staticCoordinates[spot.species]
    if coordinates then
      slot={base=slot.base,x=coordinates.x,y=coordinates.y}
    end
    if gen1 and gen1StaticOverrides[spot.species] then
      slot=gen1StaticOverrides[spot.species]
    end
    -- Gen 2 has a single-floor Victory Road rather than R/B/Y's 2F.
    -- Select a collision-checked, otherwise-unused tile there so both engines
    -- place the chamber entrance in Victory Road.
    if not gen1 and spot.species=="REGIGIGAS" then
      local gen2Entrance=nil
      for _,row in ipairs(candidates("VICTORY_ROAD")) do
        local key="VICTORY_ROAD:"..row.x..":"..row.y
        if not reserved[key] then
          gen2Entrance={base="VICTORY_ROAD",x=row.x,y=row.y}
          reserved[key]=true
          break
        end
      end
      slot=assert(gen2Entrance,"no safe Gen 2 Regigigas chamber entrance")
    end
    local mapId=slot.base
    staticCount=staticCount+1
    local level=spot.bst>=680 and 60 or spot.bst>=650 and 55
      or spot.bst>=600 and 50 or 45
    local textId="_KJT_STATIC_"..spot.species
    if spot.species=="REGIGIGAS" then
      registerRegigigasChamber(mapId,slot.x,slot.y,level)
      local chamberRegion,chamberPrefix=mapRegion(mapId)
      placements.statics.REGIGIGAS={map=REGIGIGAS_CHAMBER,nativeMap=mapId,
        label=chamberPrefix.."REGIGIGAS CHAMBER",region=chamberRegion,x=7,y=4,
        entranceX=slot.x,entranceY=slot.y}
    else
      local objectName=mapId.."_KJT_STATIC_"..spot.species
      local quest=questStatics[spot.species]
      if quest then
        registerQuestStatic(mapId,{species=spot.species,dex=spot.dex,
          x=slot.x,y=slot.y},level,textId,objectName,quest)
      else
        appendMapObject(mapId,{
          index=1000+spot.dex,name=objectName,
          pokemon=spot.species,level=level,movement="STAY",range="ANY_DIR",
          sprite="KJT_SPRITE_MONSTER",text=textId,x=slot.x,y=slot.y,
        })
        mod.content.text:register(textId,
          spot.species:gsub("_"," ").." is watching you.\nAccept its challenge?")
        local def=sourceMap(mapId)
        local label=def and def.label or mapId
        mod.content.text_pointers:patch(label,{[textId]={text=textId}})
        if label~=mapId then
          mod.content.text_pointers:patch(mapId,{[textId]={text=textId}})
        end
      end
      local staticRegion,staticPrefix=mapRegion(mapId)
      placements.statics[spot.species]={map=mapId,nativeMap=mapId,
        label=staticPrefix..pretty(mapId),region=staticRegion,x=slot.x,y=slot.y,
        questFamily=quest and quest.family or nil}
    end
  end

  local function encounterArea(species,fallback)
    local placed=placements.statics[species]
    return pretty(placed and placed.nativeMap or fallback)
  end

  local questNumber=0
  local function registerResearcher(key,mapId,script)
    questNumber=questNumber+1
    local requestedMap=mapId
    local mapOptions,seenMaps={},{}
    local function addMapOption(base)
      if base and not seenMaps[base] then
        seenMaps[base]=true
        mapOptions[#mapOptions+1]=base
      end
    end
    -- A particular cartridge can expose a valid map but no remaining safe tile
    -- after gifts and static encounters have been reserved. Keep the authored
    -- quest map as the first choice, then move only that aide to another native
    -- map in the same game rather than aborting all National Dex content.
    addMapOption(requestedMap)
    if gen1 then
      for _,base in ipairs(starterMaps) do addMapOption(base) end
    else
      local gen2ResearchMaps={}
      for _,row in pairs(gen2QuestResearchers) do
        if row.map then gen2ResearchMaps[#gen2ResearchMaps+1]=row.map end
      end
      table.sort(gen2ResearchMaps)
      for _,base in ipairs(gen2ResearchMaps) do addMapOption(base) end
    end
    for _,base in ipairs(staticMaps) do addMapOption(base) end
    -- Unlike stationary encounters, an aide must never occupy a one-tile
    -- corridor. Fully open tiles and corners with a walkable diagonal both
    -- leave the route traversable.
    local slot=assert(slotsFor(mapOptions,1,1,4,true)[1],
      "no safe native quest researcher placement for "..key)
    mapId=slot.base
    if mapId~=requestedMap and mod.log and mod.log.warn then
      mod.log:warn("%s quest aide has no safe tile on %s; using %s %d,%d",
        key,requestedMap,mapId,slot.x,slot.y)
    end
    local textId="TEXT_KND_QUEST_"..key
    local objectName=mapId.."_KND_QUEST_"..key
    appendMapObject(mapId,{
      index=1700+questNumber,name=objectName,
      movement="STAY",range="ANY_DIR",sprite="KJT_SPRITE_SCIENTIST",
      text=textId,x=slot.x,y=slot.y,
    })
    registerTalk(mapId,textId,slot.x,slot.y,script,objectName)
    local questRegion,questPrefix=mapRegion(mapId)
    placements.quests[key]={map=mapId,nativeMap=mapId,
      requestedMap=requestedMap,label=questPrefix..pretty(mapId),
      region=questRegion,x=slot.x,y=slot.y}
  end

  local birdsMap=questDefinition("BIRDS","PEWTER_CITY",nil)
  local birdsIntroduction, birdsBriefing
  if gen2Profile then
    birdsIntroduction="PROF.ELM asked me to compare three migrating storm fronts over JOHTO.\fFreezing winds, lightning, and volcanic ash each follow a different legendary bird."
    birdsBriefing="The three storm fronts point to "..encounterArea("ARTICUNO","ICE_PATH_1F")..", "..encounterArea("ZAPDOS","ROUTE_42")..", and "..encounterArea("MOLTRES","BURNED_TOWER_1F")..".\fRecord each legendary bird you encounter."
  else
    birdsIntroduction="PROF.OAK asked me to investigate three strange weather reports across KANTO.\fFreezing winds surround SEAFOAM, storms gather at the POWER PLANT, and heat rises from VICTORY ROAD."
    birdsBriefing="The three reports point to SEAFOAM, the POWER PLANT, and VICTORY ROAD.\fRecord each legendary bird you encounter."
  end
  registerResearcher("BIRDS",birdsMap,{
    {"face_player"},{"check_flag",questFlags.birdsStarted},
    {"jump_if_true","briefing"},
    {"show_text",birdsIntroduction},
    {"set_field",questFlags.birdsStarted,true},
    {"set_field",questFlags.articunoOpen,true},
    {"set_field",questFlags.zapdosOpen,true},
    {"set_field",questFlags.moltresOpen,true},
    {"show_text","Please investigate all three sites. The POKEDEX AREA page will preserve their locations."},
    {"jump","end"},{"label","briefing"},
    {"show_text",birdsBriefing},
  })

  local regisMap,regisBadge=questDefinition("REGIS","FUCHSIA_CITY","VOLCANOBADGE")
  local regisOrigin=gen2Profile and "ancient JOHTO ruins" or "ancient seals found throughout KANTO"
  registerResearcher("REGIS",regisMap,{
    {"face_player"},{"check_flag",questFlags.regisStarted},
    {"jump_if_true","status"},
    {"knd_has_badge",regisBadge},{"jump_if_false","locked"},
    {"show_text",researchProfessor.." asked me to study "..regisOrigin..".\fThe first carving describes living ROCK near "..encounterArea("REGIROCK","ROCK_TUNNEL_1F").."."},
    {"set_field",questFlags.regisStarted,true},
    {"set_field",questFlags.regirockOpen,true},
    {"show_text","Find REGIROCK first. Its seal may reveal the next part of the inscription."},
    {"jump","end"},{"label","status"},
    {"check_flag",completedFlag("REGISTEEL")},{"jump_if_true","branches"},
    {"check_flag",completedFlag("REGICE")},{"jump_if_true","steel"},
    {"check_flag",completedFlag("REGIROCK")},{"jump_if_true","ice"},
    {"show_text","The first seal points to REGIROCK near "..encounterArea("REGIROCK","ROCK_TUNNEL_1F").."."},{"jump","end"},
    {"label","ice"},{"show_text","The ROCK seal revealed an ICE inscription near "..encounterArea("REGICE","SEAFOAM_ISLANDS_B4F").."."},{"jump","end"},
    {"label","steel"},{"show_text","The ICE seal revealed a STEEL inscription near "..encounterArea("REGISTEEL","POWER_PLANT").."."},{"jump","end"},
    {"label","branches"},{"show_text","The three seals are united. Two newer inscriptions now point to "..encounterArea("REGIELEKI","POWER_PLANT").." and "..encounterArea("REGIDRAGO","VICTORY_ROAD_1F")..".\fBring ROCK, ICE, and STEEL together at the VICTORY ROAD carving to continue the oldest mystery."},
    {"jump","end"},{"label","locked"},
    {"show_text",researchProfessor.." asked me to look for you!\fIf you have the "..badgeNames[regisBadge]..", I am supposed to share his research on ancient seals."},
  })
  placements.quests.REGIS.requiredBadge=regisBadge

  local lunarMap,lunarBadge=questDefinition("LUNAR","LAVENDER_TOWN","VOLCANOBADGE")
  local dreamPlace=gen2Profile and "ECRUTEAK CITY" or "LAVENDER TOWN"
  registerResearcher("LUNAR",lunarMap,{
    {"face_player"},{"check_flag",questFlags.lunarStarted},
    {"jump_if_true","status"},
    {"knd_has_badge",lunarBadge},{"jump_if_false","locked"},
    {"show_text",researchProfessor.." asked me to investigate reports of the same dream spreading through "..dreamPlace..".\fWitnesses describe a crescent light near "..encounterArea("CRESSELIA","POKEMON_TOWER_7F").."."},
    {"set_field",questFlags.lunarStarted,true},
    {"set_field",questFlags.cresseliaOpen,true},
    {"show_text","Please find the source of that lunar light. It may be protecting the town from something darker."},
    {"jump","end"},{"label","status"},
    {"check_flag",completedFlag("DARKRAI")},{"jump_if_true","complete"},
    {"check_flag",completedFlag("CRESSELIA")},{"jump_if_true","darkrai"},
    {"show_text","Follow the crescent light near "..encounterArea("CRESSELIA","POKEMON_TOWER_7F").."."},{"jump","end"},
    {"label","darkrai"},{"show_text","CRESSELIA left a LUNAR FEATHER. Its glow points toward "..encounterArea("DARKRAI","POKEMON_TOWER_7F")..".\fThe nightmare's source should answer now."},{"jump","end"},
    {"label","complete"},{"show_text","The shared nightmares have stopped. "..researchProfessor.." will be relieved to hear your report."},
    {"jump","end"},{"label","locked"},
    {"show_text",researchProfessor.." asked me to look for you!\fIf you have the "..badgeNames[lunarBadge]..", I am supposed to share his research on "..dreamPlace.."'S strange dreams."},
  })
  placements.quests.LUNAR.requiredBadge=lunarBadge

  local function namesOf(stage)
    local names={}
    for _,species in ipairs(stage or {}) do
      names[#names+1]=species:gsub("_"," ")
    end
    return table.concat(names, ", ")
  end

  -- Every remaining family uses the same native-style research contract:
  -- show the required badge, start the investigation, then describe its
  -- capture-ordered stages.  AREA supplies the collision-selected map clues.
  for _,family in ipairs(catalog.familyQuests or {}) do
    local started=genericQuestFlags[family.id]
    local first=namesOf((family.stages or {})[1])
    local sequence={}
    for stageIndex,stage in ipairs(family.stages or {}) do
      sequence[#sequence+1]="STAGE "..stageIndex..": "..namesOf(stage)
    end
    local researcherMap,badge=questDefinition(family.id,family.map,
      family.badge or "VOLCANOBADGE")
    local badgeName=badgeNames[badge] or badge:gsub("BADGE$"," BADGE")
    local script={
      {"face_player"},{"check_flag",started},{"jump_if_true","briefing"},
      {"knd_has_badge",badge},{"jump_if_false","locked"},
      {"show_text",researchProfessor.." asked me to look for you!\fHe wants us to investigate the "..family.title..".\fBegin by finding "..first..". Check each POKEDEX AREA page for the recorded site."},
      {"set_field",started,true},{"jump","end"},
      {"label","briefing"},
      {"show_text",table.concat(sequence,".\f")..".\fEach later stage will answer after every earlier POKEMON has been caught."},
      {"jump","end"},{"label","locked"},
      {"show_text",researchProfessor.." asked me to look for you!\fIf you have the "..badgeName..", I am supposed to share his research on the "..family.title.."."},
    }
    registerResearcher(family.id,researcherMap,script)
    placements.quests[family.id].requiredBadge=badge
    placements.quests[family.id].stages=family.stages
  end

  mod.exports.progressionPlacements=placements
  mod.exports.progressionAcquisition={starterGifts=visibleStarterGifts,
    allocatedStarterSlots=starterNumber,hiddenStarterGifts=placements.hiddenStarterGifts,
    distributedStatics=staticCount,nativeStatics=native,legacyAnnexEntrance=false,
    familyQuests={birds=true,regis=true,lunar=true,
      catalog=#(catalog.familyQuests or {})},region=researchRegion,
    questProfile=gen2Profile and "gen2_johto" or "gen1_kanto"}
  if mod.log and mod.log.info then
    mod.log:info("%s progression loaded: %d gifts, %d static encounters",
      researchRegion,starterNumber,staticCount)
  end
end
