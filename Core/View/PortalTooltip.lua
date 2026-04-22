-- PortalTooltip.lua: GameTooltip assembly for portal icons. Pulls M+ season-best + affix score via
-- C_MythicPlus and caches non-secret reads so in-combat hovers still display data.

local _, addon = ...
local L = Orbit.L

local math_floor = math.floor

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Tooltip = {}
addon.PortalTooltip = Tooltip

function Tooltip.Show(ctx, anchor, data)
    local dock = ctx.dock
    local cache = ctx.state.mythicPlusCache
    local PD = addon.PortalData

    local screenWidth = GetScreenWidth()
    local dockCenterX = dock:GetCenter()
    if dockCenterX and dockCenterX < screenWidth / 2 then
        GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT", 10, 0)
    else
        GameTooltip:SetOwner(anchor, "ANCHOR_LEFT", -10, 0)
    end

    local shortName = data.short or ""
    local instanceName = data.instanceName
    local portalName = data.name or L.PLU_PORTAL_UNKNOWN

    if shortName ~= "" and instanceName then
        GameTooltip:AddLine(shortName .. " - " .. instanceName, 1, 0.82, 0)
    elseif instanceName then
        GameTooltip:AddLine(instanceName, 1, 0.82, 0)
    else
        GameTooltip:AddLine(portalName, 1, 0.82, 0)
    end

    if instanceName and instanceName ~= portalName then
        GameTooltip:AddLine(portalName, 1, 1, 1)
    end

    local categoryName = PD.CategoryNames[data.category] or data.category
    GameTooltip:AddLine(categoryName, 0.5, 0.5, 0.5)

    if data.category == "HEARTHSTONE" or data.type == "random_hearthstone" then
        local bindLocation = GetBindLocation()
        if bindLocation and bindLocation ~= "" then
            GameTooltip:AddDoubleLine(L.PLU_PORTAL_DESTINATION, bindLocation, 0.7, 0.7, 0.7, 0.5, 1, 0.5)
        end
    end

    if data.challengeModeID and data.category == "SEASONAL_DUNGEON" then
        GameTooltip:AddLine(" ")

        -- M+ getters return secret values in combat; cache only non-secret reads and fall back to cache.
        local mapID = data.challengeModeID
        local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
        local bestInfo = intimeInfo or overtimeInfo
        local cacheEntry = cache[mapID]
        if bestInfo then
            cache[mapID] = cacheEntry or {}
            cache[mapID].bestInfo = bestInfo
            cacheEntry = cache[mapID]
        elseif cacheEntry then
            bestInfo = cacheEntry.bestInfo
        end

        local _, score = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(mapID)
        local dungeonScore = 0
        if score and not issecretvalue(score) then
            cache[mapID] = cacheEntry or {}
            cache[mapID].dungeonScore = score
            dungeonScore = score
        elseif cacheEntry and cacheEntry.dungeonScore then
            dungeonScore = cacheEntry.dungeonScore
        end

        local r, g, b = addon.PortalCanvas.GetDungeonScoreColor(dungeonScore)
        GameTooltip:AddDoubleLine(L.PLU_PORTAL_RATING, dungeonScore, 1, 1, 1, r, g, b)

        if bestInfo then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L.PLU_PORTAL_BEST_RUN, 0, 1, 0)
            local level = bestInfo.level
            local durationSec = bestInfo.durationSec
            if level and durationSec and not issecretvalue(level) and not issecretvalue(durationSec) then
                local mins = math_floor(durationSec / 60)
                local secs = durationSec % 60
                GameTooltip:AddDoubleLine(L.PLU_PORTAL_LEVEL_F:format(level), string.format("%d:%02d", mins, secs), 1, 1, 1, 1, 1, 1)
                cache[mapID].level = level
                cache[mapID].durationSec = durationSec
            elseif cacheEntry and cacheEntry.level then
                local mins = math_floor(cacheEntry.durationSec / 60)
                local secs = cacheEntry.durationSec % 60
                GameTooltip:AddDoubleLine(L.PLU_PORTAL_LEVEL_F:format(cacheEntry.level), string.format("%d:%02d", mins, secs), 1, 1, 1, 1, 1, 1)
            end
        else
            GameTooltip:AddLine(L.PLU_PORTAL_NO_BEST_RUN, 0.5, 0.5, 0.5)
        end
    end

    if data.cooldown and data.cooldown > 0 then
        GameTooltip:AddLine(" ")
        local hours = math_floor(data.cooldown / 3600)
        local mins = math_floor((data.cooldown % 3600) / 60)
        local cooldownText
        if hours > 0 then
            cooldownText = L.PLU_PORTAL_CD_HM_F:format(hours, mins)
        else
            cooldownText = L.PLU_PORTAL_CD_M_F:format(mins)
        end
        GameTooltip:AddLine(cooldownText, 1, 0.4, 0.4)
    end

    GameTooltip:Show()
end
