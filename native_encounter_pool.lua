-- R/B/Y supplies a scoped definition; G/S/C supplies the global dataset.
-- Never recursively inspect a Gen II dataset before narrowing it.
return function(encDef,ctx,gen1)
  if gen1 then return encDef end
  ctx=ctx or {}
  local tables=ctx.tables or encDef
  if type(tables)~="table" or not ctx.mapId then return nil end
  local terrain=ctx.terrain
  if terrain=="indoor" then terrain="grass" end
  if terrain~="grass" and terrain~="water" then return nil end
  local maps=tables[terrain]
  local entry=type(maps)=="table" and maps[ctx.mapId]
  local slots=type(entry)=="table" and entry.slots
  if type(slots)~="table" then return nil end
  if terrain=="water" then return slots end
  local daytime=ctx.daytime or "DAY"
  if daytime=="DARK" then daytime="NITE" end
  return slots[daytime] or slots.DAY
end
