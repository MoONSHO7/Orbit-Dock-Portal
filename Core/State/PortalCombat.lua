-- PortalCombat.lua: Combat / encounter interaction gating for the portal dock.

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
        -- REGEN_DISABLED fires just before lockdown; only Hide() while the secure call is still legal.
        if not InCombatLockdown() then
            dock:Hide()
        end
        state.isEditModeActive = false
        state.isMouseOver = false
        addon.PortalNavigation.HideSearch()
    else
        dock:Show()
        dock:SetAlpha(RESTING_ALPHA)
        dock:EnableMouse(true)
        addon.PortalNavigation.RestorePropagationDefault()
        if dock:IsMouseOver() then
            state.isMouseOver = true
            addon.PortalNavigation.ShowSearch()
        end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            state.isEditModeActive = true
        end
    end
end
