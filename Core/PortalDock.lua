-- PortalDock.lua: Dock-style portal UI with edge-fade falloff and Canvas Mode components.
local _, addon = ...
local Scanner = addon.PortalScanner
local PD = addon.PortalData

---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine
local L = Orbit.L

local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition

-- [ PLUGIN REGISTRATION ] ---------------------------------------------------------------------------
local SYSTEM_ID = "Orbit_Portal"

local Plugin = Orbit:RegisterPlugin("Portal Dock", SYSTEM_ID, {
    defaults = {
        IconSize = 32,
        Spacing = 5,
        MaxVisible = 9,
        HideLongCooldowns = true,
        FadeEffect = 10,  -- 0 = off (no fade); increases toward sharper edge falloff.
        Compactness = 0,
        Favorites = {},
        ComponentPositions = {
            DungeonScore  = { anchorX = "CENTER", anchorY = "BOTTOM", offsetX = 0, offsetY = -2, justifyH = "CENTER" },
            DungeonShort  = { anchorX = "CENTER", anchorY = "TOP",    offsetX = 0, offsetY = 2,  justifyH = "CENTER" },
            FavouriteStar = { anchorX = "RIGHT",  anchorY = "TOP",    offsetX = 1, offsetY = 1,  justifyH = "RIGHT"  },
            Timer         = { anchorX = "CENTER", anchorY = "CENTER", offsetX = 0, offsetY = 0,  justifyH = "CENTER" },
        },
        DisabledComponents = { "DungeonShort", "Status" },
    },
})

-- Enable Canvas Mode: users double-click the dock to reposition DungeonScore + FavouriteStar.
Plugin.canvasMode = true

-- [ FAVORITES ] -------------------------------------------------------------------------------------
local function GetFavKey(data)
    if not data then return nil end
    return data.spellID or data.itemID or data.name
end

local function IsFavorite(data)
    local key = GetFavKey(data)
    if not key then return false end
    local favs = Plugin:GetSetting(1, "Favorites") or {}
    return favs[tostring(key)] == true
end

local function ToggleFavorite(data)
    local key = GetFavKey(data)
    if not key then return end
    local favs = Plugin:GetSetting(1, "Favorites") or {}
    local k = tostring(key)
    favs[k] = (not favs[k]) or nil
    Plugin:SetSetting(1, "Favorites", favs)
end

-- [ CANVAS COMPONENTS ] -----------------------------------------------------------------------------
local ApplyCanvasComponents = addon.PortalCanvas.ApplyIconComponents
local GetGlobalFontPath     = addon.PortalCanvas.GetGlobalFontPath
local GetDungeonScoreColor  = addon.PortalCanvas.GetDungeonScoreColor

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local RESTING_ALPHA            = 1.0
local FADE_DEFAULT             = 20
local GCD_THRESHOLD            = 2
local LONG_COOLDOWN_THRESHOLD  = 1800

local INITIAL_ICON_SIZE        = 36
local INITIAL_DOCK_WIDTH       = 44
local INITIAL_DOCK_HEIGHT      = 200
local INITIAL_DOCK_X_OFFSET    = 10
local DOCK_FRAME_LEVEL         = 100
local DOCK_FRAME_STRATA        = "MEDIUM"
local INITIAL_SCAN_DELAY       = 2
local MISSING_ICON_FILE_ID     = 134400

local ICON_TEXCOORD_MIN        = 0.08
local ICON_TEXCOORD_MAX        = 0.92
local ICON_BORDER_SCALE        = 1.1

local STAR_SIZE                = 12
local STAR_OFFSET_X            = 1
local STAR_OFFSET_Y            = 1
local STAR_SHADOW_SIZE         = 22
local STAR_SHADOW_OFFSET_X     = -4
local STAR_SHADOW_OFFSET_Y     = -6
local STAR_SHADOW_ALPHA        = 0.95
local STAR_ATLAS               = "transmog-icon-favorite"
local STAR_SHADOW_ATLAS        = "PetJournal-BattleSlot-Shadow"

local BORDER_ATLAS_FAVOURITE   = "talents-node-choiceflyout-circle-yellow"
local BORDER_ATLAS_SEASONAL    = "talents-node-choiceflyout-circle-red"
local BORDER_ATLAS_DEFAULT     = "talents-node-choiceflyout-circle-gray"

local SHEEN_ATLAS              = "talents-sheen-node"
local SHEEN_WIDTH_SCALE        = 1.0
local SHEEN_SWEEP_DURATION     = 0.5
local SHEEN_FADEIN_DURATION    = 0.15
local SHEEN_FADEOUT_DURATION   = 0.20
local SHEEN_FADEOUT_START      = 0.30
local SHEEN_PEAK_ALPHA         = 0.85

local HIGHLIGHT_COLOR_R        = 1.0
local HIGHLIGHT_COLOR_G        = 0.95
local HIGHLIGHT_COLOR_B        = 0.70
local HIGHLIGHT_COLOR_A        = 0.35

local QUESTIONMARK_ICON        = "Interface\\Icons\\INV_Misc_QuestionMark"
local CIRCULAR_MASK_PATH       = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local CLAMP_VISIBLE_MARGIN     = 30

local currentOrientation = "LEFT"

-- [ STATE ] -----------------------------------------------------------------------------------------
local dock = nil
local iconPool = nil
local visibleIcons = {}
local portalList = {}
local isEditModeActive = false
local scrollOffset = 0
local isMouseOver = false
local RefreshDock
local mythicPlusCache = {}
local pendingRefresh = false

-- Detect orientation based on dock position relative to screen center
local function DetectOrientation()
    if not dock then return "LEFT" end
    
    local screenWidth, screenHeight = GetScreenWidth(), GetScreenHeight()
    local dockCenterX = dock:GetLeft() + (dock:GetWidth() / 2)
    local dockCenterY = dock:GetBottom() + (dock:GetHeight() / 2)
    
    -- Calculate distances to each edge
    local distToLeft = dockCenterX
    local distToRight = screenWidth - dockCenterX
    local distToTop = screenHeight - dockCenterY
    local distToBottom = dockCenterY
    
    -- Find the minimum distance
    local minDist = math.min(distToLeft, distToRight, distToTop, distToBottom)
    
    -- Return orientation based on nearest edge (arc faces toward center)
    if minDist == distToLeft then
        return "LEFT"   -- Vertical, arc curves right
    elseif minDist == distToRight then
        return "RIGHT"  -- Vertical, arc curves left
    elseif minDist == distToTop then
        return "TOP"    -- Horizontal, arc curves down
    else
        return "BOTTOM" -- Horizontal, arc curves up
    end
end

-- Check if current orientation is horizontal
local function IsHorizontal()
    return currentOrientation == "TOP" or currentOrientation == "BOTTOM"
end

-- Layout math lives in PortalLayout.lua. Cache the hot helpers as upvalues.
local NormalizeMaxVisible  = addon.PortalLayout.NormalizeMaxVisible
local CalculatePosition    = addon.PortalLayout.CalculatePosition
local CalculatePerpExtent  = addon.PortalLayout.CalculatePerpExtent
local CalculateAxialExtent = addon.PortalLayout.CalculateAxialExtent

-- DRY: Format duration in seconds to readable string
local function FormatDuration(seconds)
    local hours = math_floor(seconds / 3600)
    local mins = math_floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    elseif mins > 0 then
        return string.format("%d:%02d", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

-- Icons are CENTER-anchored so scaling expands equally; axis is inset iconSize/2 from the dock edge.
local function PositionIconForOrientation(icon, dockFrame, arcOffset, centerPos, iconSize)
    icon:ClearAllPoints()
    local halfIcon = iconSize / 2
    if currentOrientation == "LEFT" then
        icon:SetPoint("CENTER", dockFrame, "TOPLEFT", halfIcon + arcOffset, -centerPos)
    elseif currentOrientation == "RIGHT" then
        icon:SetPoint("CENTER", dockFrame, "TOPRIGHT", -halfIcon - arcOffset, -centerPos)
    elseif currentOrientation == "TOP" then
        icon:SetPoint("CENTER", dockFrame, "TOPLEFT", centerPos, -halfIcon - arcOffset)
    else -- BOTTOM
        icon:SetPoint("CENTER", dockFrame, "BOTTOMLEFT", centerPos, halfIcon + arcOffset)
    end
end

-- [ COMBAT AND ENCOUNTER HANDLING ] -----------------------------------------------------------------
-- Disable during combat lockdown or while a boss encounter is in progress (even if dead).
local function CanInteract()
    if InCombatLockdown() then return false end
    if C_InstanceEncounter.IsEncounterInProgress() then return false end
    return true
end

local function UpdateCombatState()
    if not dock then return end

    local inCombatOrEncounter = InCombatLockdown() or C_InstanceEncounter.IsEncounterInProgress()

    if inCombatOrEncounter then
        -- REGEN_DISABLED fires before lockdown; only Hide() while the secure call is still legal.
        if not InCombatLockdown() then
            dock:Hide()
        end

        -- RefreshDock would touch secure attributes; defer the actual refresh to REGEN_ENABLED.
        if isEditModeActive then
            isEditModeActive = false
        end

        isMouseOver = false
    else
        dock:Show()
        dock:SetAlpha(RESTING_ALPHA)
        dock:EnableMouse(true)

        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            isEditModeActive = true
        end
    end
end

-- Request a dock refresh - queues for later if in combat
local function RequestRefresh()
    if CanInteract() then
        RefreshDock()
    else
        pendingRefresh = true
    end
end

local EdgeAlphaForIndex = addon.PortalLayout.EdgeAlphaForIndex

-- Dock is always fully opaque; alpha work happens per-icon in RefreshDock, not per frame.
local function FadeDockIn()  if dock then dock:SetAlpha(1) end end
local function FadeDockOut() if dock then dock:SetAlpha(1) end end



-- [ ICON CREATION ] ---------------------------------------------------------------------------------
local function CreatePortalIcon()
    local icon = CreateFrame("Button", nil, dock, "SecureActionButtonTemplate")
    icon:RegisterForClicks("AnyUp", "AnyDown")
    icon:SetSize(INITIAL_ICON_SIZE, INITIAL_ICON_SIZE)

    icon.mask = icon:CreateMaskTexture()
    icon.mask:SetAllPoints()
    icon.mask:SetTexture(CIRCULAR_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    -- ARTWORK sublevel 7: above the icon texture but below the OVERLAY border ring.
    icon.highlight = icon:CreateTexture(nil, "ARTWORK", nil, 7)
    icon.highlight:SetAllPoints()
    icon.highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    icon.highlight:SetVertexColor(HIGHLIGHT_COLOR_R, HIGHLIGHT_COLOR_G, HIGHLIGHT_COLOR_B, HIGHLIGHT_COLOR_A)
    icon.highlight:SetBlendMode("ADD")
    icon.highlight:AddMaskTexture(icon.mask)
    icon.highlight:Hide()

    -- Sheen: gradient bar that sweeps across the icon on click, clipped to the circular mask.
    icon.sheen = icon:CreateTexture(nil, "ARTWORK", nil, 6)
    icon.sheen:SetAtlas(SHEEN_ATLAS)
    icon.sheen:SetBlendMode("ADD")
    icon.sheen:AddMaskTexture(icon.mask)
    icon.sheen:SetAlpha(0)

    icon.sheenAnim = icon.sheen:CreateAnimationGroup()
    icon.sheenTranslate = icon.sheenAnim:CreateAnimation("Translation")
    icon.sheenTranslate:SetDuration(SHEEN_SWEEP_DURATION)
    icon.sheenTranslate:SetOrder(1)
    icon.sheenFadeIn = icon.sheenAnim:CreateAnimation("Alpha")
    icon.sheenFadeIn:SetFromAlpha(0)
    icon.sheenFadeIn:SetToAlpha(SHEEN_PEAK_ALPHA)
    icon.sheenFadeIn:SetDuration(SHEEN_FADEIN_DURATION)
    icon.sheenFadeIn:SetOrder(1)
    icon.sheenFadeOut = icon.sheenAnim:CreateAnimation("Alpha")
    icon.sheenFadeOut:SetFromAlpha(SHEEN_PEAK_ALPHA)
    icon.sheenFadeOut:SetToAlpha(0)
    icon.sheenFadeOut:SetDuration(SHEEN_FADEOUT_DURATION)
    icon.sheenFadeOut:SetStartDelay(SHEEN_FADEOUT_START)
    icon.sheenFadeOut:SetOrder(1)

    -- Icon texture (masked to be circular)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX, ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX)
    icon.texture:AddMaskTexture(icon.mask)
    
    -- Cooldown frame
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetHideCountdownNumbers(false)
    icon.cooldown:SetDrawSwipe(true)     -- Dark overlay enabled
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.7)  -- Semi-transparent black
    icon.cooldown:SetDrawEdge(true)      -- Yellow edge line
    icon.cooldown:SetUseCircularEdge(true)   -- Circular edge for round icons
    icon.cooldown:SetDrawBling(false)    -- No flash on complete
    
    -- Dedicated mask so the cooldown swipe keeps a circular clip even if the icon mask is changed.
    icon.cooldownMask = icon.cooldown:CreateMaskTexture()
    icon.cooldownMask:SetAllPoints(icon.cooldown)
    icon.cooldownMask:SetTexture(CIRCULAR_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    
    -- MaskTexture inherits Texture but can't receive AddMaskTexture; the per-region flag blocks duplicate adds (throws).
    local function ApplyCircularMaskToCooldown(cooldown, mask)
        for _, region in pairs({cooldown:GetRegions()}) do
            if region:IsObjectType("Texture")
               and not region:IsObjectType("MaskTexture")
               and not region._orbitPortalMasked then
                region:AddMaskTexture(mask)
                region._orbitPortalMasked = true
            end
        end
    end
    
    -- Apply mask immediately (for any pre-existing regions)
    ApplyCircularMaskToCooldown(icon.cooldown, icon.cooldownMask)
    
    -- SetCooldown may materialise new texture regions; re-apply the mask after each call.
    local originalSetCooldown = icon.cooldown.SetCooldown
    icon.cooldown.SetCooldown = function(self, start, duration, ...)
        originalSetCooldown(self, start, duration, ...)
        ApplyCircularMaskToCooldown(self, icon.cooldownMask)
    end
    
    -- Make cooldown text smaller and store reference for magnification scaling
    local cooldownText = icon.cooldown:GetRegions()
    if cooldownText and cooldownText.SetFont then
        local font, size, flags = cooldownText:GetFont()
        if font and size then
            local baseSize = size * 0.7
            cooldownText:SetFont(font, baseSize, flags)
            -- Store for magnification scaling
            icon.cooldownText = cooldownText
            icon.cooldownTextFont = font
            icon.cooldownTextBaseSize = baseSize
            icon.cooldownTextFlags = flags
        end
    end
    
    -- Favourite Star (Canvas Mode component) + soft shadow backdrop
    icon.FavouriteStarShadow = icon:CreateTexture(nil, "OVERLAY", nil, 5)
    icon.FavouriteStarShadow:SetAtlas(STAR_SHADOW_ATLAS)
    icon.FavouriteStarShadow:SetVertexColor(0, 0, 0, STAR_SHADOW_ALPHA)
    icon.FavouriteStarShadow:SetSize(STAR_SHADOW_SIZE, STAR_SHADOW_SIZE)
    icon.FavouriteStarShadow:Hide()

    icon.FavouriteStar = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.FavouriteStar:SetAtlas(STAR_ATLAS)
    icon.FavouriteStar:SetSize(STAR_SIZE, STAR_SIZE)
    icon.FavouriteStar:Hide()

    -- Dungeon Score (Canvas Mode component) — rendered above icon layer so it sits on top of the border.
    icon.DungeonScoreOverlay = CreateFrame("Frame", nil, icon)
    icon.DungeonScoreOverlay:SetAllPoints()
    icon.DungeonScoreOverlay:SetFrameLevel(icon:GetFrameLevel() + (Orbit.Constants.Levels and Orbit.Constants.Levels.IconOverlay or 5))
    icon.DungeonScore = icon.DungeonScoreOverlay:CreateFontString(nil, "OVERLAY")
    icon.DungeonScore:Hide()

    icon.DungeonShort = icon.DungeonScoreOverlay:CreateFontString(nil, "OVERLAY")
    icon.DungeonShort:Hide()

    -- Circular border using talent tree style ring
    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetPoint("CENTER")

    icon:SetScript("PreClick", function(self, button)
        -- Shift+Right-click: toggle favorite (non-secure, no type2 attribute set)
        if button == "RightButton" and IsShiftKeyDown() then
            local data = self.portalData
            if data then
                ToggleFavorite(data)
                RequestRefresh()
            end
            return
        end
        -- Random hearthstone re-roll: combat lockdown blocks SetAttribute, so keep the last selection.
        local data = self.portalData
        if data and data.type == "random_hearthstone" and data.availableHearthstones and not InCombatLockdown() then
            local available = data.availableHearthstones
            if #available > 0 then
                local randomIndex = math.random(1, #available)
                local chosen = available[randomIndex]
                if chosen.type == "toy" then
                    self:SetAttribute("type", "toy")
                    self:SetAttribute("toy", chosen.itemID)
                    self:SetAttribute("item", nil)
                else
                    self:SetAttribute("type", "item")
                    self:SetAttribute("item", chosen.name)
                    self:SetAttribute("toy", nil)
                end
            end
        end
    end)
    
    -- PostClick: sound feedback + talent-tree sheen sweep.
    icon:SetScript("PostClick", function(self)
        PlaySoundFile("Interface\\AddOns\\Orbit_Portal\\Audio\\switch-sound.ogg", "SFX")
        if self.sheenAnim then self.sheenAnim:Stop(); self.sheenAnim:Play() end
    end)

    -- Scripts
    icon:SetScript("OnEnter", function(self)
        if self.highlight then self.highlight:Show() end
        isMouseOver = true
        FadeDockIn()
        
        if self.portalData then
            local data = self.portalData
            
            -- Position tooltip on opposite side of screen from dock
            local screenWidth = GetScreenWidth()
            local dockCenterX = dock:GetCenter()
            if dockCenterX < screenWidth / 2 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 10, 0)
            else
                GameTooltip:SetOwner(self, "ANCHOR_LEFT", -10, 0)
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

            if data.challengeModeID and (data.category == "SEASONAL_DUNGEON") then
                GameTooltip:AddLine(" ")

                -- M+ getters return secret values in combat; cache only non-secret reads and fall back to cache.
                local mapID = data.challengeModeID
                local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
                local bestInfo = intimeInfo or overtimeInfo
                local cacheEntry = mythicPlusCache[mapID]
                if bestInfo then
                    mythicPlusCache[mapID] = cacheEntry or {}
                    mythicPlusCache[mapID].bestInfo = bestInfo
                    cacheEntry = mythicPlusCache[mapID]
                elseif cacheEntry then
                    bestInfo = cacheEntry.bestInfo
                end

                local _, score = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(mapID)
                local dungeonScore = 0
                if score and not issecretvalue(score) then
                    mythicPlusCache[mapID] = cacheEntry or {}
                    mythicPlusCache[mapID].dungeonScore = score
                    dungeonScore = score
                elseif cacheEntry and cacheEntry.dungeonScore then
                    dungeonScore = cacheEntry.dungeonScore
                end

                local r, g, b = GetDungeonScoreColor(dungeonScore)
                GameTooltip:AddDoubleLine(L.PLU_PORTAL_RATING, dungeonScore, 1, 1, 1, r, g, b)

                if bestInfo then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L.PLU_PORTAL_BEST_RUN, 0, 1, 0)

                    local level = bestInfo.level
                    local durationSec = bestInfo.durationSec
                    if level and durationSec and not issecretvalue(level) and not issecretvalue(durationSec) then
                        local mins = math_floor(durationSec / 60)
                        local secs = durationSec % 60
                        local timeText = string.format("%d:%02d", mins, secs)
                        GameTooltip:AddDoubleLine(L.PLU_PORTAL_LEVEL_F:format(level), timeText, 1, 1, 1, 1, 1, 1)

                        mythicPlusCache[mapID].level = level
                        mythicPlusCache[mapID].durationSec = durationSec
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
    end)
    
    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.highlight then self.highlight:Hide() end

        -- Check if mouse left the dock entirely (not just moved to another icon)
        if dock and not dock:IsMouseOver() then
            isMouseOver = false
            FadeDockOut()
        end
    end)
    
    return icon
end



-- [ ICON CONFIGURATION ] ----------------------------------------------------------------------------
local function ConfigureIcon(icon, data, index)
    icon.portalData = data
    icon.iconIndex = index
    icon.type = data.type
    
    local iconSize = Plugin:GetSetting(1, "IconSize")
    icon:SetSize(iconSize, iconSize)
    
    -- Size the border to match icon size (we'll scale it after setting atlas)
    local borderSize = iconSize * ICON_BORDER_SCALE  -- Slightly larger than icon for ring effect
    
    -- Border atlas tiers: yellow=favourite, red=current-season, grey=rest. displayGroup == "FAVORITE" means pinned.
    local borderAtlas
    if data.displayGroup == "FAVORITE" then
        borderAtlas = BORDER_ATLAS_FAVOURITE
    elseif data.category == "SEASONAL_DUNGEON" or data.category == "SEASONAL_RAID" then
        borderAtlas = BORDER_ATLAS_SEASONAL
    else
        borderAtlas = BORDER_ATLAS_DEFAULT
    end
    icon.border:SetAtlas(borderAtlas, false)
    icon.border:SetSize(borderSize, borderSize)
    if icon.sheen then
        local sheenW = iconSize * SHEEN_WIDTH_SCALE
        icon.sheen:SetSize(sheenW, iconSize)
        icon.sheen:ClearAllPoints()
        icon.sheen:SetPoint("RIGHT", icon, "LEFT", 0, 0)  -- Start off-icon to the left.
        if icon.sheenTranslate then
            icon.sheenTranslate:SetOffset(iconSize + sheenW, 0)  -- Sweep fully past the icon.
        end
    end

    -- FavouriteStar + DungeonScore positioning/visibility are driven by ApplyCanvasComponents.

    if data.iconAtlas then
        icon.texture:SetAtlas(data.iconAtlas)
    elseif data.icon then
        icon.texture:SetTexture(data.icon)
    else
        icon.texture:SetTexture(MISSING_ICON_FILE_ID)
    end
    
    if isEditModeActive then
        icon:SetAttribute("type", nil)
        icon:SetAttribute("spell", nil)
        icon:SetAttribute("toy", nil)
        icon:SetAttribute("item", nil)
        icon:EnableMouse(false)
    else
        icon:EnableMouse(true)
        if data.type == "spell" then
            icon:SetAttribute("type", "spell")
            icon:SetAttribute("spell", data.spellID)
        elseif data.type == "toy" then
            icon:SetAttribute("type", "toy")
            icon:SetAttribute("toy", data.itemID)
        elseif data.type == "item" then
            icon:SetAttribute("type", "item")
            icon:SetAttribute("item", data.name)
        elseif data.type == "random_hearthstone" then
            -- Random hearthstone: pick one and set up the action
            if data.availableHearthstones and #data.availableHearthstones > 0 then
                local randomIndex = math.random(1, #data.availableHearthstones)
                local chosen = data.availableHearthstones[randomIndex]
                if chosen.type == "toy" then
                    icon:SetAttribute("type", "toy")
                    icon:SetAttribute("toy", chosen.itemID)
                else
                    icon:SetAttribute("type", "item")
                    icon:SetAttribute("item", chosen.name)
                end
            end
        elseif data.type == "housing" then
            -- Player Housing: use secure action type 'teleporthome' with house attributes
            icon:SetAttribute("type", "teleporthome")
            if data.houseInfo then
                icon:SetAttribute("house-neighborhood-guid", data.houseInfo.neighborhoodGUID)
                icon:SetAttribute("house-guid", data.houseInfo.houseGUID)
                icon:SetAttribute("house-plot-id", data.houseInfo.plotID)
            end
        end
    end
    
    if data.cooldown and data.cooldown > GCD_THRESHOLD then
        -- Calculate correct startTime: current time minus elapsed time (duration - remaining)
        local duration = data.cooldownDuration or data.cooldown
        local remaining = data.cooldown
        local elapsed = duration - remaining
        local startTime = GetTime() - elapsed
        
        -- Re-apply after Clear() wipes them on recycled icons. Swipe off (square overlay), keep circular edge.
        icon.cooldown:SetDrawSwipe(false)
        icon.cooldown:SetDrawEdge(true)
        icon.cooldown:SetUseCircularEdge(true)
        icon.cooldown:SetDrawBling(false)

        icon.cooldown:SetCooldown(startTime, duration)
        icon.cooldown:Show()
        
        -- Desaturate icon texture while on cooldown
        icon.texture:SetDesaturated(true)
    else
        icon.cooldown:Clear()
        icon.cooldown:Hide()
        -- Restore icon saturation when not on cooldown
        icon.texture:SetDesaturated(false)
    end
    
    -- Edit mode forces alpha 1 so the user can see the layout; otherwise use the edge-fade target.
    local targetAlpha
    if isEditModeActive then
        targetAlpha = 1
    else
        local fadeAmount = Plugin:GetSetting(1, "FadeEffect")
        -- Legacy boolean values: true = classic cosine (20), false/nil = off (0).
        if fadeAmount == true then fadeAmount = FADE_DEFAULT
        elseif fadeAmount == false then fadeAmount = 0 end
        local maxVisibleSetting = Plugin:GetSetting(1, "MaxVisible")
        local normMaxVisible = NormalizeMaxVisible(maxVisibleSetting, #portalList)
        targetAlpha = EdgeAlphaForIndex(index, normMaxVisible, fadeAmount)
    end
    icon.currentAlpha = targetAlpha
    icon:SetAlpha(targetAlpha)
    icon:Show()
end

-- [ DOCK LAYOUT ] -----------------------------------------------------------------------------------
-- Assign to forward-declared variable so OnEnter can call it
RefreshDock = function()
    if not dock or not CanInteract() then return end
    
    -- Hide all current icons
    for _, icon in ipairs(visibleIcons) do
        icon:Hide()
        icon:ClearAllPoints()
    end
    wipe(visibleIcons)
    
    -- Get fresh portal list (filtered - no dividers from scanner)
    local rawList = Scanner:GetOrderedList()
    
    -- displayGroup clusters favourites without clobbering item.category (preserves seasonal art/score).
    for _, item in ipairs(rawList) do
        item.displayGroup = IsFavorite(item) and "FAVORITE" or item.category
    end

    local hideLongCooldowns = Plugin:GetSetting(1, "HideLongCooldowns")
    local enabledCategories = Plugin:GetSetting(1, "EnabledCategories") or {}
    portalList = {}
    for _, item in ipairs(rawList) do
        local cooldownRemaining = item.cooldown or 0
        local isCurrentSeason = item.category == "SEASONAL_DUNGEON" or item.category == "SEASONAL_RAID"
        local cooldownPass = not hideLongCooldowns or isCurrentSeason or cooldownRemaining < LONG_COOLDOWN_THRESHOLD
        -- Favorites always show. Other items pass when their real category is enabled.
        local categoryPass = item.displayGroup == "FAVORITE" or enabledCategories[item.category] ~= false
        if cooldownPass and categoryPass then
            table.insert(portalList, item)
        end
    end

    -- Sort by CategoryOrder priority using displayGroup (clusters favorites together).
    local catPriority = {}
    for i, cat in ipairs(PD.CategoryOrder) do catPriority[cat] = i end
    local orderIndex = {}
    for i, item in ipairs(portalList) do orderIndex[item] = i end
    table.sort(portalList, function(a, b)
        local pa = catPriority[a.displayGroup] or 999
        local pb = catPriority[b.displayGroup] or 999
        if pa ~= pb then return pa < pb end
        return orderIndex[a] < orderIndex[b]
    end)
    
    local totalItems = #portalList
    
    if totalItems == 0 then
        dock:Hide()
        return
    end
    
    local iconSize = Plugin:GetSetting(1, "IconSize")
    local spacing = Plugin:GetSetting(1, "Spacing")
    local maxVisible = Plugin:GetSetting(1, "MaxVisible")
    
    -- Detect and update orientation based on dock position
    currentOrientation = DetectOrientation()
    
    -- Normalize maxVisible using helper
    maxVisible = NormalizeMaxVisible(maxVisible, totalItems)
    
    local compactness = Plugin:GetSetting(1, "Compactness") / 100
    local iconPoolIndex = 0

    for displayIndex = 0, maxVisible - 1 do
        iconPoolIndex = iconPoolIndex + 1

        local actualIndex = ((scrollOffset + displayIndex) % totalItems) + 1
        local data = portalList[actualIndex]

        if data then
            if not iconPool then iconPool = {} end
            local icon = iconPool[iconPoolIndex]
            if not icon then
                icon = CreatePortalIcon()
                table.insert(iconPool, icon)
            end

            ConfigureIcon(icon, data, displayIndex)
            ApplyCanvasComponents(Plugin, icon, data, mythicPlusCache, IsFavorite(data))

            local axialPos, arcOffset = CalculatePosition(displayIndex, maxVisible, iconSize, spacing, compactness)
            icon.stableCenterPos = axialPos
            PositionIconForOrientation(icon, dock, arcOffset, axialPos, iconSize)

            table.insert(visibleIcons, icon)
        end
    end

    local maxIconSize = iconSize
    local maxMagBonus = 0

    local dockLength = math_max(CalculateAxialExtent(maxVisible, iconSize, spacing, compactness) + (maxIconSize - iconSize), iconSize)
    local perpExtent = CalculatePerpExtent(maxVisible, iconSize, spacing, compactness)
    local dockThickness = maxIconSize + perpExtent + maxMagBonus + 2
    
    if IsHorizontal() then
        dock:SetWidth(dockLength)
        dock:SetHeight(dockThickness)
    else
        dock:SetWidth(dockThickness)
        dock:SetHeight(dockLength)
    end

    -- Semi-clamp: drag past the edge but keep CLAMP_VISIBLE_MARGIN on-screen; near/far edges flip sign.
    local marginX = math_max(0, dock:GetWidth() - CLAMP_VISIBLE_MARGIN)
    local marginY = math_max(0, dock:GetHeight() - CLAMP_VISIBLE_MARGIN)
    dock:SetClampRectInsets(marginX, -marginX, -marginY, marginY)

    dock:Show()
end

-- [ SCROLL HANDLING ] -------------------------------------------------------------------------------
local function OnMouseWheel(self, delta)
    if not CanInteract() then return end

    local totalIcons = #portalList
    if totalIcons == 0 then return end

    
    -- SHIFT+SCROLL: Jump to next/previous category
    if IsShiftKeyDown() then
        -- Find current center item's category
        local maxVisible = Plugin:GetSetting(1, "MaxVisible")
        maxVisible = NormalizeMaxVisible(maxVisible, totalIcons)
        local centerSlot = math.floor(maxVisible / 2)
        local currentCenterIndex = ((scrollOffset + centerSlot) % totalIcons) + 1
        local currentCategory = portalList[currentCenterIndex] and portalList[currentCenterIndex].displayGroup
        
        if delta > 0 then
            -- Scroll UP (previous category): search backwards for different category
            for offset = 1, totalIcons - 1 do
                local checkIndex = ((currentCenterIndex - 1 - offset) % totalIcons) + 1
                local item = portalList[checkIndex]
                if item and item.displayGroup ~= currentCategory then
                    -- Found a different group, now find the FIRST item of that group
                    local targetCategory = item.displayGroup
                    local firstOfCategory = checkIndex
                    for back = 1, totalIcons do
                        local prevIndex = ((checkIndex - 1 - back) % totalIcons) + 1
                        local prevItem = portalList[prevIndex]
                        if not prevItem or prevItem.displayGroup ~= targetCategory then
                            break
                        end
                        firstOfCategory = prevIndex
                    end
                    -- Set scroll to center this item
                    scrollOffset = (firstOfCategory - 1 - centerSlot + totalIcons) % totalIcons
                    break
                end
            end
        else
            -- Scroll DOWN (next category): search forwards for different category
            for offset = 1, totalIcons - 1 do
                local checkIndex = ((currentCenterIndex - 1 + offset) % totalIcons) + 1
                local item = portalList[checkIndex]
                if item and item.displayGroup ~= currentCategory then
                    -- Found first item of next group, center it
                    scrollOffset = (checkIndex - 1 - centerSlot + totalIcons) % totalIcons
                    break
                end
            end
        end
    else
        -- Normal scroll: move one item at a time
        scrollOffset = (scrollOffset - delta) % totalIcons
    end
    
    RefreshDock()
end

-- [ DOCK CREATION ] ---------------------------------------------------------------------------------
local function CreateDock()
    dock = CreateFrame("Frame", "OrbitPortalDock", UIParent)
    dock:SetSize(INITIAL_DOCK_WIDTH, INITIAL_DOCK_HEIGHT)
    dock:SetPoint("LEFT", UIParent, "LEFT", INITIAL_DOCK_X_OFFSET, 0)

    OrbitEngine.Pixel:Enforce(dock)

    dock:SetFrameStrata(DOCK_FRAME_STRATA)
    dock:SetFrameLevel(DOCK_FRAME_LEVEL)
    dock:SetClampedToScreen(true)
    -- Permissive until RefreshDock tightens the insets; otherwise RestorePosition snaps saved off-screen positions.
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    dock:SetClampRectInsets(sw, -sw, -sh, sh)
    dock:EnableMouse(true)
    dock:SetMovable(true)
    dock:RegisterForDrag("LeftButton")


    -- Scroll wheel
    dock:SetScript("OnMouseWheel", OnMouseWheel)
    
    -- Mouse enter: Fade in dock
    dock:SetScript("OnEnter", function(self)
        isMouseOver = true
        FadeDockIn()
    end)
    
    -- Mouse leave: Fade out dock
    dock:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then
            isMouseOver = false
            FadeDockOut()
        end
    end)
    
    -- Start in resting alpha state
    dock:SetAlpha(RESTING_ALPHA)
    
    -- Engine-level auto-orient during edit-mode drag; callback is registered later in OnLoad.
    dock.orbitAutoOrient = true

    -- Canvas Mode: render a representative icon with DungeonScore + FavouriteStar draggable.
    function dock:CreateCanvasPreview(options)
        options = options or {}
        local iconSize = Plugin:GetSetting(1, "IconSize")
        local iconTexture = QUESTIONMARK_ICON
        -- Prefer a seasonal dungeon icon so DungeonScore has something meaningful to render.
        for _, item in ipairs(portalList or {}) do
            if item.category == "SEASONAL_DUNGEON" and item.icon then
                iconTexture = item.icon
                break
            end
        end

        -- Custom preview: round icon with talent-ring border (matches live dock icon).
        local preview = CreateFrame("Frame", nil, options.parent or UIParent)
        preview:SetSize(iconSize, iconSize)
        preview.sourceFrame = self
        preview.sourceWidth = iconSize
        preview.sourceHeight = iconSize
        preview.borderInset = 0
        preview.previewScale = 1
        preview.components = {}
        preview.systemIndex = 1

        local mask = preview:CreateMaskTexture()
        mask:SetAllPoints()
        mask:SetTexture(CIRCULAR_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

        local iconTex = preview:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX, ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX)
        iconTex:SetTexture(iconTexture)
        iconTex:AddMaskTexture(mask)

        -- Seasonal icons get the gold ring; fallback icon gets the grey ring.
        local borderAtlas = iconTexture ~= QUESTIONMARK_ICON and BORDER_ATLAS_SEASONAL or BORDER_ATLAS_DEFAULT
        local borderTex = preview:CreateTexture(nil, "OVERLAY")
        borderTex:SetAtlas(borderAtlas, false)
        borderTex:SetPoint("CENTER")
        borderTex:SetSize(iconSize * ICON_BORDER_SCALE, iconSize * ICON_BORDER_SCALE)

        local savedPositions = Plugin:GetSetting(1, "ComponentPositions") or {}
        local fontPath = GetGlobalFontPath()

        OrbitEngine.IconCanvasPreview:AttachTextComponents(preview, {
            { key = "Timer",        preview = "5",   anchorX = "CENTER", anchorY = "CENTER", offsetX = 0, offsetY = 0  },
            { key = "DungeonScore", preview = "285", anchorX = "CENTER", anchorY = "BOTTOM", offsetX = 0, offsetY = -2 },
            { key = "DungeonShort", preview = "AA",  anchorX = "CENTER", anchorY = "TOP",    offsetX = 0, offsetY = 2  },
        }, savedPositions, fontPath)

        -- Favourite Star: render the actual atlas as a draggable texture (not a text glyph).
        local CreateDraggableComponent = OrbitEngine.CanvasMode and OrbitEngine.CanvasMode.CreateDraggableComponent
        if CreateDraggableComponent then
            local AnchorToCenter = OrbitEngine.PositionUtils.AnchorToCenter
            local halfW, halfH = preview.sourceWidth / 2, preview.sourceHeight / 2
            local srcStar = preview:CreateTexture(nil, "ARTWORK")
            srcStar:SetAtlas(STAR_ATLAS)
            srcStar:SetSize(STAR_SIZE, STAR_SIZE)
            srcStar:Hide()
            srcStar.orbitOriginalWidth, srcStar.orbitOriginalHeight = 12, 12

            local saved = savedPositions.FavouriteStar or {}
            local data = {
                anchorX = saved.anchorX or "RIGHT",
                anchorY = saved.anchorY or "TOP",
                offsetX = saved.offsetX or 1,
                offsetY = saved.offsetY or 1,
                justifyH = saved.justifyH or "RIGHT",
                overrides = saved.overrides,
            }
            local startX, startY = saved.posX, saved.posY
            if startX == nil or startY == nil then
                local cx, cy = AnchorToCenter(data.anchorX, data.anchorY, data.offsetX, data.offsetY, halfW, halfH)
                startX = startX or cx
                startY = startY or cy
            end
            local comp = CreateDraggableComponent(preview, "FavouriteStar", srcStar, startX, startY, data)
            if comp then
                comp:SetFrameLevel(preview:GetFrameLevel() + Orbit.Constants.Levels.Overlay)
                preview.components.FavouriteStar = comp
            end
        end

        return preview
    end

    return dock
end

-- [ LIFECYCLE ] -------------------------------------------------------------------------------------
function Plugin:OnLoad()
    -- Create the dock frame
    dock = CreateDock()
    self.frame = dock

    -- Visibility Engine: centralised oocFade / opacity / hideMounted / mouseOver / showWithTarget.
    Orbit.OOCFadeMixin:ApplyOOCFade(dock, self, 1)

    -- Fire-and-forget prime so the first tooltip hover has score info without needing the M+ panel.
    C_MythicPlus.RequestMapInfo()
    C_MythicPlus.RequestCurrentAffixes()
    
    -- Register for Edit Mode selection and settings
    dock.editModeName = "Portal Dock"
    dock.systemIndex = 1
    dock.orbitNoSnap = true  -- Disable anchoring/snapping to other frames
    
    OrbitEngine.Frame:AttachSettingsListener(dock, self, 1)

    -- Keeps the dock under the cursor when an orientation swap changes its width/height mid-drag.
    OrbitEngine.Frame:RegisterOrientationCallback(dock, function(orientation)
        if currentOrientation == orientation then return end

        local cursorX, cursorY = GetCursorPosition()
        local scale = dock:GetEffectiveScale()
        cursorX, cursorY = cursorX / scale, cursorY / scale
        local dockCenterX = dock:GetLeft() + (dock:GetWidth() / 2)
        local dockCenterY = dock:GetBottom() + (dock:GetHeight() / 2)
        local offsetX = cursorX - dockCenterX
        local offsetY = cursorY - dockCenterY

        currentOrientation = orientation
        RefreshDock()

        if dock.orbitIsDragging then
            local newCenterX = cursorX - offsetX
            local newCenterY = cursorY - offsetY
            local newLeft = newCenterX - (dock:GetWidth() / 2)
            local newBottom = newCenterY - (dock:GetHeight() / 2)
            dock:ClearAllPoints()
            dock:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
        end
    end)

    -- If Edit Mode is already active (plugin loaded mid-session), show selection.
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        dock:SetMovable(true)
        OrbitEngine.FrameSelection:UpdateVisuals(dock)
    end
    
    OrbitEngine.Frame:RestorePosition(dock, self, 1)
    
    -- Event handling for combat state and scanning
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    -- Scan triggers
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")  -- Fires on login AND reload
    self.eventFrame:RegisterEvent("SPELLS_CHANGED")
    self.eventFrame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")  -- Housing data async response
    
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_ENABLED" then
            UpdateCombatState()
            -- Process any queued refresh
            if pendingRefresh then
                pendingRefresh = false
                RefreshDock()
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            UpdateCombatState()
        elseif event == "ENCOUNTER_START" then
            UpdateCombatState()
        elseif event == "ENCOUNTER_END" then
            if not InCombatLockdown() then
                UpdateCombatState()
                if pendingRefresh then
                    pendingRefresh = false
                    RefreshDock()
                end
            else
                pendingRefresh = true
            end
        elseif event == "PLAYER_LOGIN" then
            -- Spell APIs aren't queryable at the instant PLAYER_LOGIN fires; small delay avoids a blank first scan.
            C_Timer.After(INITIAL_SCAN_DELAY, function()
                Scanner:RequestHousingData()
                RequestRefresh()
            end)
        elseif event == "SPELLS_CHANGED" then
            RequestRefresh()
        elseif event == "PLAYER_ENTERING_WORLD" then
            Scanner:RequestHousingData()
            RequestRefresh()
        elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
            local houseInfos = ...
            Scanner:UpdateHousingCache(houseInfos)
            RequestRefresh()
        end
    end)

    self:RegisterStandardEvents()
    self:RegisterVisibilityEvents()

    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            isEditModeActive = true
            RequestRefresh()
        end, self)

        EventRegistry:RegisterCallback("EditMode.Exit", function()
            isEditModeActive = false
            RequestRefresh()
        end, self)
    end

    RequestRefresh()
end

function Plugin:UpdateVisibility()
    if not dock then return end
    local shouldHide = (C_PetBattles and C_PetBattles.IsInBattle()) or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
        or (Orbit.MountedVisibility and Orbit.MountedVisibility:ShouldHide())
    dock:SetAlpha(shouldHide and 0 or RESTING_ALPHA)
end

function Plugin:ApplySettings()
    if not dock then return end
    RequestRefresh()
end

-- [ SETTINGS UI ] -----------------------------------------------------------------------------------
function Plugin:AddSettings(dialog, systemFrame)
    local self_ = self
    local SB = OrbitEngine.SchemaBuilder
    local schema = { controls = {}, extraButtons = {} }

    SB:SetTabRefreshCallback(dialog, self, systemFrame)
    local currentTab = SB:AddSettingsTabs(schema, dialog, { "Layout", "Categories" }, "Layout")

    if currentTab == "Layout" then
        table.insert(schema.controls, { type = "checkbox", key = "HideLongCooldowns", label = L.PLU_PORTAL_HIDE_LONG_CD, default = true })
        table.insert(schema.controls, {
            type = "slider", key = "FadeEffect", label = L.PLU_PORTAL_FADE_EFFECT,
            min = 0, max = 100, step = 5, default = 20,
            formatter = function(v) return v == 0 and L.PLU_PORTAL_FADE_OFF or L.PLU_PORTAL_FADE_PCT_F:format(v) end,
        })
        table.insert(schema.controls, { type = "slider", key = "IconSize", label = L.PLU_PORTAL_ICON_SIZE, min = 24, max = 40, step = 2, default = 34 })
        table.insert(schema.controls, { type = "slider", key = "Spacing", label = L.PLU_PORTAL_ICON_PADDING, min = 0, max = 20, step = 1, default = 3 })
        table.insert(schema.controls, { type = "slider", key = "MaxVisible", label = L.PLU_PORTAL_MAX_VISIBLE, min = 3, max = 21, step = 2, default = 9 })
        table.insert(schema.controls, { type = "slider", key = "Compactness", label = L.PLU_PORTAL_COMPACTNESS, min = 0, max = 100, step = 1, default = 0 })
    elseif currentTab == "Categories" then
        local counts = {}
        for _, item in ipairs(Scanner:GetOrderedList()) do
            counts[item.category] = (counts[item.category] or 0) + 1
        end
        -- FAVORITE is always on: pinned portals show even when their source category is off.
        for _, cat in ipairs(PD.CategoryOrder) do
            local count = counts[cat] or 0
            if cat ~= "FAVORITE" and count > 0 then
                local label = PD.CategoryNames[cat] or cat
                table.insert(schema.controls, {
                    type = "checkbox", key = "Category_" .. cat, label = label, default = true,
                    valueText = "|cFFFFD100" .. count .. "|r",
                    onChange = function(val)
                        local enabled = self_:GetSetting(1, "EnabledCategories") or {}
                        enabled[cat] = val
                        self_:SetSetting(1, "EnabledCategories", enabled)
                        if RefreshDock and CanInteract() then RefreshDock() end
                    end,
                    getValue = function()
                        local enabled = self_:GetSetting(1, "EnabledCategories") or {}
                        return enabled[cat] ~= false
                    end,
                })
            end
        end
    end

    OrbitEngine.Config:Render(dialog, systemFrame, self, schema)
end

addon.PortalDock = Plugin

-- [ COMMAND HANDLER ] -------------------------------------------------------------------------------
function Plugin:HandleCommand(cmd)
    cmd = cmd or ""

    if cmd == "scan" then
        wipe(mythicPlusCache)
        if CanInteract() then
            RefreshDock()
        end
        Orbit:Print(L.CMD_PORTAL_SCAN_DONE)
    else
        print(L.CMD_PORTAL_HEADER)
        print(L.CMD_PORTAL_HELP_SCAN)
    end
end
