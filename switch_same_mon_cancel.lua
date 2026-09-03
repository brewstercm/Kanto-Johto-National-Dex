-- Selecting the currently-active Pokemon from the free SHIFT-style party
-- picker behaves like pressing B: close the picker and continue without a
-- switch.  This deliberately does NOT alter ordinary voluntary battle
-- switching, and a fainted active mon still uses the forced-replacement path.
return function(mod)
  local PartyMenu = require("src.ui.PartyMenu")
  if PartyMenu._kjSameMonCancelInstalled then return end
  PartyMenu._kjSameMonCancelInstalled = true

  local vanillaUpdate = PartyMenu.update

  local function activeMon(menu)
    -- Gen 1: PartyMenu carries the BattleState directly.
    local battle = menu and menu.battle
    if type(battle) == "table" and battle.player and battle.player.mon then
      return battle.player.mon
    end

    -- Gold: PartyMenu.battle is a boolean.  The live BattleState is directly
    -- underneath the picker on StateStack and its model is state.battle.
    local game = menu and menu.game
    local states = game and game.stack and game.stack.states
    if type(states) == "table" then
      for i = #states - 1, 1, -1 do
        local state = states[i]
        if state then
          if state.player and state.player.mon then return state.player.mon end
          local model = state.battle
          if type(model) == "table" and model.player then return model.player end
        end
      end
    end
    return nil
  end

  local function isFreeShiftPicker(menu, active)
    if not (menu and active and (active.hp or 0) > 0) then return false end

    -- Gen 1's post-KO SHIFT picker is the forceSwitch form.  A normal PKMN
    -- command uses battle=true/onSwitch but forceSwitch=false and first opens
    -- SWITCH/STATS/CANCEL, so leave that path completely vanilla.
    if menu.forceSwitch ~= nil then
      return menu.forceSwitch == true
    end

    -- Gold's equivalent is the battle party list WITHOUT BattleMonMenu.
    -- Voluntary mid-turn switching sets wantsBattleSubmenu=true; faint
    -- replacement also has no submenu, but active.hp==0 above excludes it.
    return menu.battle == true and menu.wantsBattleSubmenu ~= true
  end

  local function cancelLikeB(menu)
    local game = menu.game
    -- PartyMenu normally records the cursor before B on Gold.  Gen 1's saved
    -- party cursor is also harmless to retain here.
    if menu.storeCursor then pcall(menu.storeCursor, menu) end

    if game and game.data then
      local ok, Sound = pcall(require, "src.core.Sound")
      if ok and Sound and Sound.play then pcall(Sound.play, game.data, "Press_AB") end
    end

    if game and game.stack and game.stack.top and game.stack:top() == menu then
      game.stack:pop()
    end
    if type(menu.onCancel) == "function" then menu.onCancel() end
  end

  PartyMenu.update = function(self, dt)
    local input = self and self.game and self.game.input
    if input and input:wasPressed("a")
       and not self.submenu and not self.switchFrom and not self.swapFrom then
      local party = self.party or (self.game.save and self.game.save.party) or {}
      local chosen = party[self.index]
      local active = activeMon(self)
      if chosen and chosen == active and isFreeShiftPicker(self, active) then
        cancelLikeB(self)
        return
      end
    end
    return vanillaUpdate(self, dt)
  end
end
