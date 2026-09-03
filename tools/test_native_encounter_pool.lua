local selectPool=assert(loadfile("native_encounter_pool.lua"))()
local day={{species="PIDGEY",level=5}}
local night={{species="GASTLY",level=5}}
local water={{species="POLIWAG",level=10}}
local tables={
  grass={ROUTE_31={slots={DAY=day,MORN=day,NITE=night}},
    OTHER_ROUTE={slots={DAY={{species="HYPNO",level=16}}}}},
  water={ROUTE_31={slots=water}},
  fishGroups={pond={{species="GYARADOS",level=40}}},
}
local function selected(terrain,time,map)
  return selectPool(tables,{mapId=map or "ROUTE_31",terrain=terrain,daytime=time},false)
end
assert(selected("grass","DAY")==day)
assert(selected("grass","MORN")==day)
assert(selected("grass","NITE")==night)
assert(selected("grass","DARK")==night)
assert(selected("indoor","DAY")==day)
assert(selected("grass",nil)==day)
assert(selected("grass","UNKNOWN")==day)
assert(selected("water","NITE")==water)
assert(selected("grass","DAY","MISSING")==nil)
assert(selected("fishing","DAY")==nil)
assert(selectPool(nil,{},false)==nil)
assert(selectPool({slots=day},{mapId="ROUTE_31",terrain="grass"},false)==nil)
local swarm={grass={ROUTE_31={slots={DAY=night}}}}
assert(selectPool(tables,{tables=swarm,mapId="ROUTE_31",terrain="grass"},false)==night)
local gen1={rate=10,slots=day}
assert(selectPool(gen1,{},true)==gen1)
assert(loadfile("main.lua")) -- parse the actual hook integration as well
-- Execute the maintained hook, not a reimplementation of its collector.
local file=assert(io.open("main.lua","r"))
local source=file:read("*a"); file:close()
local first=assert(source:find("local completionPoolCache={}",1,true))
local last=assert(source:find("-- Integrated QoL",first,true))
local hook
local env=setmetatable({
  ownModule=function() return selectPool end,
  isGen1=function() return false end,
  gameSharkNoBattles=function() return false end,
  generationOf=function(species) return species=="SHINX" and 4 or 1 end,
  extraEncounters={maps={ROUTE_31={grass={{species="SHINX",level=5}}}}},
  mod={hooks={wrap=function(_,name,fn) hook=fn end}},
},{__index=_G})
assert(load(source:sub(first,last-1),"encounter hook","t",env))()
for _,time in ipairs({"DAY","NITE","DARK"}) do
  local seen={}
  for generation=1,2 do
    local calls=0
    local result=hook(function() return {species="PIDGEY",level=5} end,tables,{
      mapId="ROUTE_31",terrain="grass",kind="wild",daytime=time,
      rng=function(lo,hi)
        calls=calls+1
        return calls==1 and generation or hi
      end,
    })
    assert(result.level==5)
    seen[result.species]=true
  end
  assert(seen.SHINX)
  assert(seen[time=="DAY" and "PIDGEY" or "GASTLY"])
  assert(not seen.HYPNO and not seen.POLIWAG and not seen.GYARADOS)
end
print("Native pool regression tests passed: map, terrain, time, swarm, Gen I isolation")
