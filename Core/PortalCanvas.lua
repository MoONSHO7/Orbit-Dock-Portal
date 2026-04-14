-- PortalCanvas.lua: Canvas Mode per-icon apply for DungeonScore, DungeonShort, Timer, FavouriteStar.
-- Reads positions/overrides/disabled-list from the Plugin and writes to the icon's child elements.

local _, addon = ...
local Orbit = Orbit
local OrbitEngine = Orbit.Engine

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local DEFAULT_FONT_SIZE        = 10
local DEFAULT_COOLDOWN_SIZE    = 12
local DUNGEON_SCORE_DEFAULT_OY = -2
local DUNGEON_SHORT_DEFAULT_OY = 2
local STAR_DEFAULT_OX          = 1
local STAR_DEFAULT_OY          = 1
local STAR_SHADOW_Y_OFFSET     = -2

local SCORE_COLOR_LEGENDARY = { 1.00, 0.50, 0.00 }
local SCORE_COLOR_EPIC      = { 0.64, 0.21, 0.93 }
local SCORE_COLOR_RARE      = { 0.00, 0.44, 0.87 }
local SCORE_COLOR_UNCOMMON  = { 0.12, 1.00, 0.00 }
local SCORE_COLOR_COMMON    = { 1.00, 1.00, 1.00 }

local SCORE_TIER_LEGENDARY = 300
local SCORE_TIER_EPIC      = 250
local SCORE_TIER_RARE      = 200
local SCORE_TIER_UNCOMMON  = 100

-- Cache hot globals.
local math_floor = math.floor
local ipairs = ipairs

local Canvas = {}
addon.PortalCanvas = Canvas

-- [ HELPERS ] ---------------------------------------------------------------------------------------
local function GetDungeonScoreColor(score)
    local c
    if     score >= SCORE_TIER_LEGENDARY then c = SCORE_COLOR_LEGENDARY
    elseif score >= SCORE_TIER_EPIC      then c = SCORE_COLOR_EPIC
    elseif score >= SCORE_TIER_RARE      then c = SCORE_COLOR_RARE
    elseif score >= SCORE_TIER_UNCOMMON  then c = SCORE_COLOR_UNCOMMON
    else                                      c = SCORE_COLOR_COMMON
    end
    return c[1], c[2], c[3]
end

local function GetGlobalFontPath()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local fontName = Orbit.db and Orbit.db.GlobalSettings and Orbit.db.GlobalSettings.Font
    if fontName and LSM then return LSM:Fetch("font", fontName) or STANDARD_TEXT_FONT end
    return STANDARD_TEXT_FONT
end

-- Populate the M+ cache entry for a dungeon if it's missing. Lazy lookup so scores
-- appear without requiring a tooltip hover first.
local function EnsureDungeonScoreCached(challengeModeID, mythicPlusCache)
    if not C_MythicPlus or not challengeModeID then return end
    local entry = mythicPlusCache[challengeModeID]
    if entry and entry.dungeonScore then return end
    local ok, _, score = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, challengeModeID)
    if ok and score then
        mythicPlusCache[challengeModeID] = mythicPlusCache[challengeModeID] or {}
        mythicPlusCache[challengeModeID].dungeonScore = score
    end
end

local function BuildDisabledSet(plugin)
    local disabledList = plugin:GetSetting(1, "DisabledComponents") or {}
    local disabled = {}
    for _, k in ipairs(disabledList) do disabled[k] = true end
    return disabled
end

-- [ PER-COMPONENT APPLIERS ] ------------------------------------------------------------------------
local function ApplyDungeonScore(icon, data, pos, disabled, cache)
    local OverrideUtils = OrbitEngine.OverrideUtils
    local ApplyTextPosition = OrbitEngine.PositionUtils and OrbitEngine.PositionUtils.ApplyTextPosition
    local eligible = not disabled.DungeonScore and data
        and data.category == "SEASONAL_DUNGEON" and data.challengeModeID
    if eligible then EnsureDungeonScoreCached(data.challengeModeID, cache) end
    local cacheEntry = eligible and cache[data.challengeModeID]
    if not (eligible and cacheEntry and cacheEntry.dungeonScore) then
        icon.DungeonScore:Hide()
        return
    end
    local score = cacheEntry.dungeonScore
    local fontPath = GetGlobalFontPath()
    if OverrideUtils then
        local overrides = pos and pos.overrides or {}
        OverrideUtils.ApplyFontOverrides(icon.DungeonScore, overrides, DEFAULT_FONT_SIZE, fontPath)
    else
        icon.DungeonScore:SetFont(fontPath, DEFAULT_FONT_SIZE, Orbit.Skin:GetFontOutline())
    end
    icon.DungeonScore:SetText(tostring(math_floor(score)))
    icon.DungeonScore:SetTextColor(GetDungeonScoreColor(score))
    if ApplyTextPosition then
        ApplyTextPosition(icon.DungeonScore, icon.DungeonScoreOverlay, pos, "CENTER", 0, DUNGEON_SCORE_DEFAULT_OY)
    end
    icon.DungeonScore:Show()
end

local function ApplyDungeonShort(icon, data, pos, disabled)
    local OverrideUtils = OrbitEngine.OverrideUtils
    local ApplyTextPosition = OrbitEngine.PositionUtils and OrbitEngine.PositionUtils.ApplyTextPosition
    if disabled.DungeonShort or not (data and data.short) then
        icon.DungeonShort:Hide()
        return
    end
    local fontPath = GetGlobalFontPath()
    if OverrideUtils then
        local overrides = pos and pos.overrides or {}
        OverrideUtils.ApplyFontOverrides(icon.DungeonShort, overrides, DEFAULT_FONT_SIZE, fontPath)
    else
        icon.DungeonShort:SetFont(fontPath, DEFAULT_FONT_SIZE, Orbit.Skin:GetFontOutline())
    end
    icon.DungeonShort:SetText(data.short)
    icon.DungeonShort:SetTextColor(1, 1, 1)
    if ApplyTextPosition then
        ApplyTextPosition(icon.DungeonShort, icon.DungeonScoreOverlay, pos, "CENTER", 0, DUNGEON_SHORT_DEFAULT_OY)
    end
    icon.DungeonShort:Show()
end

-- Timer uses Blizzard's CooldownFrameTemplate's built-in countdown FontString. Disabling
-- goes through SetHideCountdownNumbers so the template doesn't re-show each tick.
local function ApplyTimer(icon, pos, disabled)
    local OverrideUtils = OrbitEngine.OverrideUtils
    local ApplyTextPosition = OrbitEngine.PositionUtils and OrbitEngine.PositionUtils.ApplyTextPosition
    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
        icon.cooldown:SetHideCountdownNumbers(disabled.Timer == true)
    end
    if icon.cooldownText and not disabled.Timer then
        local fontPath = GetGlobalFontPath()
        if OverrideUtils then
            local overrides = pos and pos.overrides or {}
            local baseSize = icon.cooldownTextBaseSize or DEFAULT_COOLDOWN_SIZE
            OverrideUtils.ApplyOverrides(icon.cooldownText, overrides, { fontSize = baseSize, fontPath = fontPath })
            local f, sz, flags = icon.cooldownText:GetFont()
            if f    then icon.cooldownTextFont     = f    end
            if sz   then icon.cooldownTextBaseSize = sz   end
            if flags then icon.cooldownTextFlags   = flags end
        end
        if ApplyTextPosition then
            ApplyTextPosition(icon.cooldownText, icon, pos, "CENTER", 0, 0)
        end
    end
end

local function ApplyFavouriteStar(icon, pos, disabled, isFavourite)
    local ApplyTextPosition = OrbitEngine.PositionUtils and OrbitEngine.PositionUtils.ApplyTextPosition
    if disabled.FavouriteStar or not isFavourite then
        icon.FavouriteStar:Hide()
        icon.FavouriteStarShadow:Hide()
        return
    end
    if ApplyTextPosition then
        ApplyTextPosition(icon.FavouriteStar, icon, pos, "TOPRIGHT", STAR_DEFAULT_OX, STAR_DEFAULT_OY)
        icon.FavouriteStarShadow:ClearAllPoints()
        icon.FavouriteStarShadow:SetPoint("CENTER", icon.FavouriteStar, "CENTER", 0, STAR_SHADOW_Y_OFFSET)
    end
    icon.FavouriteStar:Show()
    icon.FavouriteStarShadow:Show()
end

-- [ PUBLIC API ] ------------------------------------------------------------------------------------
-- isFavourite: the caller passes the result of their own IsFavorite(data) check so this module
-- stays decoupled from the favourites storage.
function Canvas.ApplyIconComponents(plugin, icon, data, mythicPlusCache, isFavourite)
    local positions = plugin:GetSetting(1, "ComponentPositions") or {}
    local disabled = BuildDisabledSet(plugin)

    ApplyDungeonScore (icon, data, positions.DungeonScore,  disabled, mythicPlusCache)
    ApplyDungeonShort (icon, data, positions.DungeonShort,  disabled)
    ApplyTimer        (icon,       positions.Timer,         disabled)
    ApplyFavouriteStar(icon,       positions.FavouriteStar, disabled, isFavourite)
end

-- Exposed for callers that only need the shared font path resolver (e.g. the Canvas preview).
Canvas.GetGlobalFontPath = GetGlobalFontPath
