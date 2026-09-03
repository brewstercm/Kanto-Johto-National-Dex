-- Keep the closed Poké Ball visible through SHAKE_ANIM's initial pause.
-- Loaded through main.lua's integrated-mod initializer contract.
return function(mod)
  local AnimPlayer = require("src.battle.AnimPlayer")

  if AnimPlayer.__kjBallContinuityPatched then return end
  AnimPlayer.__kjBallContinuityPatched = true

  local originalStart = AnimPlayer.start
  AnimPlayer.start = function(self, moveId, attackerIsPlayer, opts)
    local ret = originalStart(self, moveId, attackerIsPlayer, opts)
    if moveId ~= "SHAKE_ANIM" or type(self.steps) ~= "table" then return ret end

    -- Find the first authored frame that actually contains the resting ball.
    local firstVisible
    for _, st in ipairs(self.steps) do
      if st and type(st.sprites) == "table" and #st.sprites > 0 then
        firstVisible = st.sprites
        break
      end
    end
    if not firstVisible then return ret end

    -- Fill only the leading blank setup/pause frames. Later blank frames remain
    -- untouched because they may be intentional parts of the animation.
    for _, st in ipairs(self.steps) do
      if st and type(st.sprites) == "table" and #st.sprites == 0 then
        st.sprites = firstVisible
      else
        break
      end
    end
    return ret
  end
end
