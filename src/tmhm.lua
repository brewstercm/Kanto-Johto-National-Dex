-- Adds cartridge-native TM/HM compatibility to species supplied by this mod.
-- The generated payload records canonical compatibility, while this module
-- resolves each move against the live cartridge registry. That last step is
-- important because Red and Gold do not always spell the same move id alike.

local M = {}

local function normalise(id)
  if type(id) ~= "string" then return nil end
  return (id:upper():gsub("[^A-Z0-9]", ""))
end

local function liveMoves(registry)
  local out = {}
  local ok, values = pcall(function() return registry:each() end)
  if not ok then return out end
  if type(values) == "function" then
    for id in values do
      local key = normalise(id)
      if key and out[key] == nil then out[key] = id end
    end
  elseif type(values) == "table" then
    for _, id in ipairs(values) do
      local key = normalise(id)
      if key and out[key] == nil then out[key] = id end
    end
  end
  return out
end

function M.install(mod, payload, generation)
  local records = payload and payload[generation == 2 and "gen2" or "gen1"]
  if type(records) ~= "table" then
    return { species = 0, links = 0, unavailable = 0, failed = 0 }
  end

  local nativeMax = generation == 2 and 251 or 151
  local moves = liveMoves(mod.content.moves)
  local species, links, unavailable, failed = 0, 0, 0, 0

  for id, entry in pairs(records) do
    local ok, current = pcall(function() return mod.content.pokemon:get(id) end)
    -- Forms are mod-owned even when their National Dex number belongs to a
    -- cartridge-native base species (for example RATTATA_ALOLA).
    local modOwned = ok and type(current) == "table"
      and ((tonumber(entry.dex) or 0) > nativeMax or current.form ~= nil)
    if modOwned then
      local merged, seen = {}, {}
      for _, move in ipairs(current.tmhm or {}) do
        if type(move) == "string" and not seen[move] then
          seen[move] = true
          merged[#merged + 1] = move
        end
      end
      for _, requested in ipairs(entry.moves or {}) do
        local move = moves[normalise(requested)]
        if move then
          if not seen[move] then
            seen[move] = true
            merged[#merged + 1] = move
            links = links + 1
          end
        else
          -- A payload may be shared with a cartridge whose move registry is
          -- smaller. Never leave an unresolved reference in a species row.
          unavailable = unavailable + 1
        end
      end
      table.sort(merged)
      if #merged > 0 then
        local patched = pcall(function()
          mod.content.pokemon:patch(id, { tmhm = merged })
        end)
        if patched then species = species + 1 else failed = failed + 1 end
      end
    end
  end

  mod.log:info("native TM/HM compatibility gen=%d species=%d links=%d "
    .. "unavailable=%d failed=%d", generation, species, links, unavailable,
    failed)
  return { species = species, links = links, unavailable = unavailable,
           failed = failed }
end

setmetatable(M, { __call = function(_, ...) return M.install(...) end })
return M
