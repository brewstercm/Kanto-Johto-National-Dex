-- Gives every enemy trainer slot an independent 1-9 roll while preserving
-- the original slot's level and other authored fields. In R/B/Y, a 1 keeps
-- the authored species. In G/S/C, its own generation keeps it unchanged.
-- Other rolls choose from that generation with this priority: same
-- primary type + evolution stage, same primary type, same stage, then any
-- ordinary species from the rolled generation.

local M = {}
local LIMITS={151,251,386,493,649,721,809,905,1025}

local function generationOf(dex)
  dex=tonumber(dex)
  if not dex then return nil end
  for generation,limit in ipairs(LIMITS) do
    if dex<=limit then return generation end
  end
end

local function trainerIds(registry)
  local ids={}
  local ok,values=pcall(function() return registry:each() end)
  if not ok then return ids end
  if type(values)=="function" then
    for id in values do ids[#ids+1]=id end
  elseif type(values)=="table" then
    for key,value in pairs(values) do
      local id=type(key)=="number" and value or key
      if type(id)=="string" then ids[#ids+1]=id end
    end
  end
  table.sort(ids)
  return ids
end

local function excludedSpecies(specials)
  local excluded={}
  for _,row in ipairs((specials and specials.staticSpecies) or {}) do
    if type(row.species)=="string" then excluded[row.species]=true end
  end
  return excluded
end

function M.buildPool(mod,dexArt,stageData,specials)
  local pool={}
  for generation=1,9 do pool[generation]={} end
  local excluded=excludedSpecies(specials)
  for id,art in pairs(dexArt or {}) do
    local generation=generationOf(art.dex)
    local ok,record=pcall(function() return mod.content.pokemon:get(id) end)
    if generation and not excluded[id] and ok and type(record)=="table"
        and type(record.types)=="table" and type(record.types[1])=="string" then
      local evolution=stageData and stageData[id]
      pool[generation][#pool[generation]+1]={
        id=id, primaryType=record.types[1], types=record.types,
        stage=tonumber(evolution and evolution.stage) or 1,
      }
    end
  end
  for generation=1,9 do
    table.sort(pool[generation],function(a,b) return a.id<b.id end)
  end
  return pool
end

local function matching(rows,originalId,primaryType,stage,wantType,wantStage)
  local out={}
  for _,candidate in ipairs(rows or {}) do
    if candidate.id~=originalId
        and (not wantType or candidate.primaryType==primaryType)
        and (not wantStage or candidate.stage==stage) then
      out[#out+1]=candidate
    end
  end
  return out
end

function M.choose(rows,originalId,primaryType,stage,rng,gymType)
  if gymType then
    local themed={}
    for _,candidate in ipairs(rows or {}) do
      local fits=candidate.primaryType==gymType
      for _,kind in ipairs(candidate.types or {}) do
        if kind==gymType then fits=true end
      end
      if fits then themed[#themed+1]=candidate end
    end
    if #themed==0 then return originalId end
    rows=themed
  end
  local priorities={{true,true},{true,false},{false,true},{false,false}}
  for _,priority in ipairs(priorities) do
    local choices=matching(rows,originalId,primaryType,stage,
      priority[1],priority[2])
    if #choices>0 then return choices[rng(1,#choices)].id end
  end
  -- A one-species generation/type/stage bucket may contain only the original.
  -- Keeping it is safer than manufacturing an invalid species reference.
  return rows and rows[1] and rows[1].id or originalId
end

local function copySlot(slot)
  local out={}
  for key,value in pairs(slot) do out[key]=value end
  return out
end

function M.mixParty(mod,party,pool,stageData,rng,dexArt,gen2,gymType)
  local mixed,replaced,rolls={},0,{}
  for index,slot in ipairs(party or {}) do
    local out=copySlot(slot)
    local original=slot.species
    local ok,record=pcall(function() return mod.content.pokemon:get(original) end)
    if type(original)=="string" and ok and type(record)=="table"
        and type(record.types)=="table" and type(record.types[1])=="string" then
      local generation=rng(1,9)
      rolls[index]=generation
      -- R/B/Y retains the explicit Gen I keep roll. G/S/C instead compares
      -- the roll with the authored species' generation before replacement.
      local originalGeneration=generationOf(dexArt and dexArt[original]
        and dexArt[original].dex)
      local keepGeneration=gen2 and originalGeneration or 1
      if generation~=keepGeneration then
        local evolution=stageData and stageData[original]
        local stage=tonumber(evolution and evolution.stage) or 1
        local theme=gymType=="ORIGINAL" and record.types[1] or gymType
        out.species=M.choose(pool[generation],original,record.types[1],stage,rng,theme)
        if out.species~=original then replaced=replaced+1 end
      end
    end
    mixed[index]=out
  end
  return mixed,replaced,rolls
end

local GYM_MAPS={
  PEWTER_GYM="ROCK",CERULEAN_GYM="WATER",VERMILION_GYM="ELECTRIC",
  CELADON_GYM="GRASS",FUCHSIA_GYM="POISON",SAFFRON_GYM="PSYCHIC",
  CINNABAR_GYM="FIRE",SEAFOAM_GYM="FIRE",
  VIOLET_GYM="FLYING",AZALEA_GYM="BUG",GOLDENROD_GYM="NORMAL",
  ECRUTEAK_GYM="GHOST",CIANWOOD_GYM="FIGHTING",OLIVINE_GYM="STEEL",
  MAHOGANY_GYM="ICE",BLACKTHORN_GYM_1F="DRAGON",BLACKTHORN_GYM_2F="DRAGON",
  FIGHTING_DOJO="FIGHTING",SAFFRON_FIGHTING_DOJO="FIGHTING",
}
local LEADERS={BROCK="ROCK",MISTY="WATER",LT_SURGE="ELECTRIC",
  LTSURGE="ELECTRIC",ERIKA="GRASS",SABRINA="PSYCHIC",BLAINE="FIRE",
  FALKNER="FLYING",BUGSY="BUG",WHITNEY="NORMAL",MORTY="GHOST",
  CHUCK="FIGHTING",JASMINE="STEEL",PRYCE="ICE",CLAIR="DRAGON",JANINE="POISON",
  BLUE="ORIGINAL"}

function M.gymThemes(mod)
  local byParty,byIndex={},{}
  for _,id in ipairs(trainerIds(mod.content.trainers)) do
    local record=mod.content.trainers:get(id)
    if record and record.index then byIndex[record.index]=id end
  end
  local data=mod.game and mod.game.data or {}
  local maps={}
  for id,theme in pairs(GYM_MAPS) do maps[id]=theme end
  maps.VIRIDIAN_GYM="VIRIDIAN"
  for mapId,theme in pairs(maps) do
    local def
    if mod.content.maps then
      local ok,value=pcall(function() return mod.content.maps:get(mapId) end)
      if ok then def=value end
    end
    def=def or (data.maps and data.maps[mapId]) or (data.gen2Maps and data.gen2Maps[mapId])
    for _,object in ipairs((def and def.objects) or {}) do
      local trainer=object.trainer
      local gen2=type(trainer)=="table"
      local class=gen2 and (byIndex[trainer.class] or trainer.class) or object.trainerClass
      local member=gen2 and trainer.member or object.trainerParty
      if class and member then
        local resolved=theme=="VIRIDIAN" and (gen2 and "ORIGINAL" or "GROUND") or theme
        byParty[tostring(class).."#"..tostring(member)]=resolved
      end
    end
  end
  return byParty
end

function M.install(mod,dexArt,stageData,specials,rng)
  rng=rng or math.random
  local pool=M.buildPool(mod,dexArt,stageData,specials)
  local gymThemes=M.gymThemes(mod)
  local poolCounts={}
  for generation=1,9 do poolCounts[generation]=#pool[generation] end
  local trainers,parties,slots,replaced,failed=0,0,0,0,0
  for _,id in ipairs(trainerIds(mod.content.trainers)) do
    local ok,record=pcall(function() return mod.content.trainers:get(id) end)
    if ok and type(record)=="table" and type(record.trainers)=="table" then
      -- G/S/C classes contain named trainer members, each with its own party.
      -- Copy members rather than dropping names, trainerType or rematch IDs.
      local mixed,changed={},0
      for memberIndex,member in ipairs(record.trainers) do
        local out=copySlot(member)
        local theme=gymThemes[id.."#"..memberIndex] or LEADERS[id:gsub("^OPP_","")]
        local result,count=M.mixParty(mod,member.party,pool,stageData,rng,dexArt,true,theme)
        out.party=result
        mixed[memberIndex]=out
        changed=changed+count
        parties=parties+1
        slots=slots+#result
      end
      if #mixed>0 then
        local patched=pcall(function()
          mod.content.trainers:patch(id,{trainers=mixed})
        end)
        if patched then
          trainers=trainers+1
          replaced=replaced+changed
        else
          failed=failed+1
        end
      end
    elseif ok and type(record)=="table" and type(record.parties)=="table" then
      local mixed={}
      local changed=0
      for partyIndex,party in ipairs(record.parties) do
        local theme=gymThemes[id.."#"..partyIndex] or LEADERS[id:gsub("^OPP_","")]
        if id=="OPP_KOGA" then theme="POISON" end
        local result,count=M.mixParty(mod,party,pool,stageData,rng,nil,false,theme)
        mixed[partyIndex]=result
        changed=changed+count
        parties=parties+1
        slots=slots+#result
      end
      if #mixed>0 then
        local patched=pcall(function()
          mod.content.trainers:patch(id,{parties=mixed})
        end)
        if patched then
          trainers=trainers+1
          replaced=replaced+changed
        else
          failed=failed+1
        end
      end
    end
  end
  mod.log:info("trainer generation mix trainers=%d parties=%d slots=%d "
    .. "replaced=%d failed=%d",trainers,parties,slots,replaced,failed)
  return {trainers=trainers,parties=parties,slots=slots,
    replaced=replaced,failed=failed,poolCounts=poolCounts}
end

setmetatable(M,{__call=function(_,...) return M.install(...) end})
return M
