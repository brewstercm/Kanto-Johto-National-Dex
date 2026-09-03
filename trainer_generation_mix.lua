-- Gives every enemy trainer slot an independent 1-9 roll while preserving
-- the original slot's level and other authored fields. A 1 keeps the authored
-- species. Rolls 2-9 choose from that generation with this priority: same
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
        id=id, primaryType=record.types[1],
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

function M.choose(rows,originalId,primaryType,stage,rng)
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

function M.mixParty(mod,party,pool,stageData,rng)
  local mixed,replaced,rolls={},0,{}
  for index,slot in ipairs(party or {}) do
    local out=copySlot(slot)
    local original=slot.species
    local ok,record=pcall(function() return mod.content.pokemon:get(original) end)
    if type(original)=="string" and ok and type(record)=="table"
        and type(record.types)=="table" and type(record.types[1])=="string" then
      local generation=rng(1,9)
      rolls[index]=generation
      -- Generation 1 is the explicit vanilla result: retain this trainer's
      -- authored species rather than exchanging it for a different Gen 1 mon.
      if generation~=1 then
        local evolution=stageData and stageData[original]
        local stage=tonumber(evolution and evolution.stage) or 1
        out.species=M.choose(pool[generation],original,record.types[1],stage,rng)
        if out.species~=original then replaced=replaced+1 end
      end
    end
    mixed[index]=out
  end
  return mixed,replaced,rolls
end

function M.install(mod,dexArt,stageData,specials,rng)
  rng=rng or math.random
  local pool=M.buildPool(mod,dexArt,stageData,specials)
  local poolCounts={}
  for generation=1,9 do poolCounts[generation]=#pool[generation] end
  local trainers,parties,slots,replaced,failed=0,0,0,0,0
  for _,id in ipairs(trainerIds(mod.content.trainers)) do
    local ok,record=pcall(function() return mod.content.trainers:get(id) end)
    if ok and type(record)=="table" and type(record.parties)=="table" then
      local mixed={}
      local changed=0
      for partyIndex,party in ipairs(record.parties) do
        local result,count=M.mixParty(mod,party,pool,stageData,rng)
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
