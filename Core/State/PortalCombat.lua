-- PortalCombat.lua: Combat / encounter interaction gating. All protected frame ops route through
-- CanInteract(); UpdateState(ctx) reconciles dock visibility on REGEN_ENABLED/DISABLED.

local _, addon = ...

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local RESTING_ALPHA = 1.0

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Combat = {}
addon.PortalCombat = Combat

function Combat.CanInteract()
    if InCombatLockdown() then return false end
    if C_InstanceEncounter.IsEncounterInProgress() then return false end
    return true
end

function Combat.UpdateState(ctx)
    local dock = ctx.dock
    if not dock then return end

    local state = ctx.state
    local inCombatOrEncounter = InCombatLockdown() or C_InstanceEncounter.IsEncounterInProgress()

    if inCombatOrEncounter then
        -- REGEN_DISABLED fires before lockdown; only Hide() while the secure call is still legal.
        if not InCombatLockdown() then
            dock:Hide()
        end
        state.isEditModeActive = false
        state.isMouseOver = false
        -- Capture frame is a child of the dock; hiding the dock hides it too, so bindings stay free.
        addon.PortalNavigation.HideSearch()
    else
        dock:Show()
        dock:SetAlpha(RESTING_ALPHA)
        dock:EnableMouse(true)
        -- Covers /reload-during-combat: Install had to skip SetPropagateKeyboardInput under lockdown.
        addon.PortalNavigation.RestorePropagationDefault()
        -- Restore capture if the mouse is still parked over the dock from before combat.
        if dock:IsMouseOver() then
            state.isMouseOver = true
            addon.PortalNavigation.ShowSearch()
        end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            state.isEditModeActive = true
        end
    end
end
