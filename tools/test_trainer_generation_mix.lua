local mix=assert(loadfile("trainer_generation_mix.lua"))()
local records={PIDGEY={types={"NORMAL","FLYING"}},
  SENTRET={types={"NORMAL"}},FURRET={types={"NORMAL"}},
  HOOTHOOT={types={"NORMAL","FLYING"}},LUGIA={types={"PSYCHIC"}}}
local dex={PIDGEY={dex=16},SENTRET={dex=161},FURRET={dex=162},
  HOOTHOOT={dex=163},LUGIA={dex=249}}
local stages={PIDGEY={stage=1},SENTRET={stage=1},FURRET={stage=2},HOOTHOOT={stage=1}}
local specials={staticSpecies={{species="LUGIA"}}}
local moves={"TACKLE","GUST"}
local slot={species="PIDGEY",level=9,item="BERRY",moves=moves}
local member={name="FALKNER",id="FALKNER1",index=1,
  trainerType="TRAINERTYPE_ITEM_MOVES",party={slot}}
for _,generation in ipairs({"gen1","gold","silver","crystal"}) do
  for _,roll in ipairs({1,2}) do
    local original=generation=="gen1" and {parties={{slot}}} or {trainers={member}}
    local patched
    local mod={content={
      pokemon={get=function(_,id) return records[id] end},
      trainers={each=function() return {"TEST"} end,
        get=function() return original end,
        patch=function(_,id,patch) assert(id=="TEST"); patched=patch end},
    },log={info=function() end}}
    local stats=mix.install(mod,dex,stages,specials,function(lo,hi)
      return hi==9 and roll or lo
    end)
    assert(stats.trainers==1 and stats.parties==1 and stats.slots==1 and stats.failed==0)
    assert(stats.poolCounts[2]==3) -- legendary excluded
    local out
    if generation=="gen1" then out=patched.parties[1][1]
    else
      local trainer=patched.trainers[1]
      assert(trainer.name==member.name and trainer.id==member.id)
      assert(trainer.index==member.index and trainer.trainerType==member.trainerType)
      out=trainer.party[1]
    end
    assert(out.level==9 and out.item=="BERRY" and out.moves==moves)
    assert(slot.species=="PIDGEY" and member.party[1]==slot)
    if roll==1 then assert(out.species=="PIDGEY" and stats.replaced==0)
    else
      assert(out.species=="HOOTHOOT" and stats.replaced==1)
      assert(stages[out.species].stage==1)
      assert(records[out.species].types[1]=="NORMAL")
    end
  end
end
-- Verify the same fallback order used by Gen I, and Gen I roll preservation
-- even when the authored Pokemon itself is from Gen II.
local first=function() return 1 end
assert(mix.choose({{id="TYPE",primaryType="NORMAL",stage=2},
  {id="STAGE",primaryType="FIRE",stage=1}},"ORIGINAL","NORMAL",1,first)=="TYPE")
assert(mix.choose({{id="STAGE",primaryType="FIRE",stage=1}},
  "ORIGINAL","NORMAL",1,first)=="STAGE")
local mod={content={pokemon={get=function(_,id) return records[id] end}}}
local result,count,rolls=mix.mixParty(mod,{{species="SENTRET",level=5}}, {},stages,first)
assert(result[1].species=="SENTRET" and count==0 and rolls[1]==1)
local pool=mix.buildPool(mod,dex,stages,specials)
local function rollGeneration(n)
  return function(lo,hi) return hi==9 and n or lo end
end
-- Gen II: preserve only when the roll matches the authored species generation.
local kept,keptCount=mix.mixParty(mod,{{species="SENTRET",level=5}},pool,
  stages,rollGeneration(2),dex,true)
assert(kept[1].species=="SENTRET" and keptCount==0)
local replaced,replacedCount=mix.mixParty(mod,{{species="SENTRET",level=5}},pool,
  stages,rollGeneration(1),dex,true)
assert(replaced[1].species=="PIDGEY" and replacedCount==1)
local native,nativeCount=mix.mixParty(mod,{{species="PIDGEY",level=5}},pool,
  stages,rollGeneration(1),dex,true)
assert(native[1].species=="PIDGEY" and nativeCount==0)
assert(mix.choose(pool[2],"PIDGEY","NORMAL",1,first,"FLYING")=="HOOTHOOT")
assert(mix.choose(pool[2],"PIDGEY","NORMAL",1,first,"DRAGON")=="PIDGEY")
-- Theme is mandatory even when only an evolution-stage mismatch is available.
assert(mix.choose({{id="BIRD",primaryType="NORMAL",types={"NORMAL","FLYING"},stage=2},
  {id="MAMMAL",primaryType="NORMAL",types={"NORMAL"},stage=1}},
  "PIDGEY","NORMAL",1,first,"FLYING")=="BIRD")
local classes={
  BIRD_KEEPER={index=24,trainers={member,member}},
  FALKNER={index=1,trainers={member}},
  OPP_JR_TRAINER_M={parties={{slot},{slot}}},
}
local patches={}
local gymMod={content={pokemon=mod.content.pokemon,
  trainers={each=function() return {"BIRD_KEEPER","FALKNER","OPP_JR_TRAINER_M"} end,
    get=function(_,id) return classes[id] end,
    patch=function(_,id,value) patches[id]=value end},
  maps={get=function(_,id)
    if id=="VIOLET_GYM" then return {objects={{trainer={class=24,member=1}}}} end
    if id=="PEWTER_GYM" then return {objects={{trainerClass="OPP_JR_TRAINER_M",trainerParty=1}}} end
  end},
},log={info=function() end}}
mix.install(gymMod,dex,stages,specials,function(lo,hi) return hi==9 and 2 or hi end)
assert(patches.BIRD_KEEPER.trainers[1].party[1].species=="HOOTHOOT")
assert(patches.BIRD_KEEPER.trainers[2].party[1].species=="SENTRET")
assert(patches.FALKNER.trainers[1].party[1].species=="HOOTHOOT")
-- No Rock choice exists in this fixture: keep the gym member, not the whole class.
assert(patches.OPP_JR_TRAINER_M.parties[1][1].species=="PIDGEY")
assert(patches.OPP_JR_TRAINER_M.parties[2][1].species=="SENTRET")
print("Trainer mix tests passed: generation rules, gym members/leaders, secondary types, no off-theme fallback")
