-- TeleportDock.lua
-- Main plugin file: macOS Dock-style teleport UI with magnification effect

local _, addon = ...
local Scanner = addon.TeleportScanner
local TD = addon.TeleportData

-- Get Orbit reference
local Orbit = _G.Orbit or LibStub and LibStub("Orbit", true)
if not Orbit then
    -- Orbit not loaded, cannot register plugin
    return
end

-- Get Engine reference for Edit Mode integration
local OrbitEngine = Orbit.Engine

-- Get LibQTip for enhanced tooltips
local LibQTip = LibStub and LibStub("LibQTip-1.0", true)
local tooltip = nil  -- Reusable tooltip reference

-- ============================================================================
-- PLUGIN REGISTRATION
-- ============================================================================

local SYSTEM_ID = "Orbit_Teleport"

local Plugin = Orbit:RegisterPlugin("Teleport Dock", SYSTEM_ID, {
    defaults = {
        Magnification = true,
        MaxVisible = 11,
        IconSize = 36,
        HoverScale = 1.33,
        Spacing = 4,
        ShowCooldowns = true,
    },
})

-- ============================================================================
-- STATE
-- ============================================================================

local dock = nil
local iconPool = nil
local visibleIcons = {}
local teleportList = {}
local isEditModeActive = false
local scrollOffset = 0
local isMouseOver = false
local RefreshDock  -- Forward declaration for use in OnEnter
local mythicPlusCache = {}  -- Cache for M+ ratings to survive encounter lockouts

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local ANIMATION_SPEED = 12 -- Higher = faster animation
local RESTING_ALPHA = 0.0 -- Dock alpha when not hovered
local DEFAULT_ARC_DEPTH = 5 -- How far the curve indents (pixels) - subtle curve

-- Orientation enum: determines layout direction and arc direction
-- "LEFT" = vertical icons, arc curves right (toward center)
-- "RIGHT" = vertical icons, arc curves left (toward center)
-- "TOP" = horizontal icons, arc curves down (toward center)
-- "BOTTOM" = horizontal icons, arc curves up (toward center)
local currentOrientation = "LEFT"  -- Default

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

-- DRY: Normalize maxVisible to be odd and within bounds
local function NormalizeMaxVisible(maxVisible, totalItems)
    if maxVisible % 2 == 0 then
        maxVisible = maxVisible - 1
    end
    return math.max(3, math.min(maxVisible, totalItems or maxVisible))
end

-- DRY: Calculate arc offset for a given position
local function CalculateArcOffset(displayIndex, maxVisible, iconSize, arcDepth)
    local normalizedPos = displayIndex / (maxVisible - 1)
    local curveValue = math.sin(normalizedPos * math.pi)
    local edgeOffset = -iconSize * 0.8
    return edgeOffset + (arcDepth - edgeOffset) * curveValue
end

-- DRY: Format duration in seconds to readable string
local function FormatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    elseif mins > 0 then
        return string.format("%d:%02d", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

-- DRY: Position icon based on current orientation
local function PositionIconForOrientation(icon, dockFrame, arcOffset, pos, iconHalfSize, anchorFromCenter)
    icon:ClearAllPoints()
    if currentOrientation == "LEFT" then
        icon:SetPoint("TOPLEFT", dockFrame, "TOPLEFT", arcOffset, -(pos - (anchorFromCenter and iconHalfSize or 0)))
    elseif currentOrientation == "RIGHT" then
        icon:SetPoint("TOPRIGHT", dockFrame, "TOPRIGHT", -arcOffset, -(pos - (anchorFromCenter and iconHalfSize or 0)))
    elseif currentOrientation == "TOP" then
        icon:SetPoint("TOPLEFT", dockFrame, "TOPLEFT", pos - (anchorFromCenter and iconHalfSize or 0), -arcOffset)
    else -- BOTTOM
        icon:SetPoint("BOTTOMLEFT", dockFrame, "BOTTOMLEFT", pos - (anchorFromCenter and iconHalfSize or 0), arcOffset)
    end
end

-- ============================================================================
-- ANIMATION STATE
-- ============================================================================

local animationFrame = nil
local targetDockAlpha = RESTING_ALPHA
local currentDockAlpha = RESTING_ALPHA

-- Magnification state
local magnificationOffset = 0      -- Virtual scroll offset caused by magnification
local targetMagOffset = 0          -- Target magnification offset for smooth animation

-- ============================================================================
-- COMBAT AND ENCOUNTER HANDLING
-- ============================================================================

local function CanInteract()
    -- Disable during combat lockdown OR during boss encounters (even if dead)
    if InCombatLockdown() then return false end
    if C_Encounter and C_Encounter.IsEncounterInProgress and C_Encounter.IsEncounterInProgress() then return false end
    return true
end

local function UpdateCombatState()
    if not dock then return end
    
    local inCombatOrEncounter = InCombatLockdown() or 
        (C_Encounter and C_Encounter.IsEncounterInProgress and C_Encounter.IsEncounterInProgress())
    
    if inCombatOrEncounter then
        -- COMBAT/ENCOUNTER STARTED
        -- Only hide if we're NOT yet in combat lockdown (REGEN_DISABLED fires before lockdown)
        if not InCombatLockdown() then
            dock:Hide()
        end
        
        -- Force exit edit mode awareness during combat
        if isEditModeActive then
            isEditModeActive = false
            -- Note: We can't call RefreshDock() here because we're in combat
            -- It will be refreshed when combat ends
        end
        
        -- Stop any running animations
        if animationFrame then
            animationFrame:SetScript("OnUpdate", nil)
        end
        
        isMouseOver = false
    else
        -- COMBAT ENDED: Restore dock (safe to call Show() when not in combat)
        dock:Show()
        dock:SetAlpha(RESTING_ALPHA)
        dock:EnableMouse(true)
        
        -- Check if Edit Mode is still open (player may have opened it before combat)
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            isEditModeActive = true
        end
    end
end

-- ============================================================================
-- DOCK ANIMATION - With Icon Alpha Fading
-- ============================================================================

local MIN_ICON_ALPHA = 0.4 -- Minimum alpha for icons not being hovered

-- Utility: Lerp (linear interpolation)
local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- Calculate icon scale and alpha targets based on cursor position
local function CalculateIconTargets()
    if not dock or not isMouseOver then return end
    
    local magnificationEnabled = Plugin:GetSetting(1, "Magnification")
    -- Treat nil as true (default enabled)
    if magnificationEnabled == false then
        -- Magnification explicitly disabled, reset all targets
        for _, icon in ipairs(visibleIcons) do
            icon.targetScale = 1
            icon.targetAlpha = 1
        end
        return
    end
    
    local iconSize = Plugin:GetSetting(1, "IconSize") or 36
    local spacing = Plugin:GetSetting(1, "Spacing") or 4
    local hoverScale = Plugin:GetSetting(1, "HoverScale") or 1.33
    
    -- Get cursor position relative to dock (orientation-aware)
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    cursorX = cursorX / uiScale
    cursorY = cursorY / uiScale
    
    -- Get reference position based on orientation
    local dockRef, cursorPos
    if IsHorizontal() then
        dockRef = dock:GetLeft()
        cursorPos = cursorX
    else
        dockRef = dock:GetTop()
        cursorPos = cursorY
    end
    
    if not dockRef then return end
    
    local closestDistance = math.huge
    local closestIndex = 0
    
    -- First pass: find the closest icon
    for i, icon in ipairs(visibleIcons) do
        -- Calculate STABLE center position based on base size and index
        local stableCenter
        if IsHorizontal() then
            local baseSlotLeft = dockRef + ((i - 1) * (iconSize + spacing))
            stableCenter = baseSlotLeft + (iconSize / 2)
        else
            local baseSlotTop = dockRef - ((i - 1) * (iconSize + spacing))
            stableCenter = baseSlotTop - (iconSize / 2)
        end
        
        local pixelDistance = math.abs(cursorPos - stableCenter)
        
        -- Track closest icon
        if pixelDistance < closestDistance then
            closestDistance = pixelDistance
            closestIndex = i
        end
        
        -- Default to no magnification
        icon.targetScale = 1
        icon.targetAlpha = 1
    end
    
    -- Determine which icons are "edge" icons that shouldn't magnify
    local totalVisible = #visibleIcons
    local centerCount = math.ceil(totalVisible / 3)
    local centerStart = math.floor((totalVisible - centerCount) / 2) + 1
    local centerEnd = centerStart + centerCount - 1
    local isEdgeIcon = function(index)
        return index < centerStart or index > centerEnd
    end
    
    -- Only magnify the closest icon (and not if it's an edge icon)
    if closestIndex > 0 and closestDistance < iconSize and not isEdgeIcon(closestIndex) then
        visibleIcons[closestIndex].targetScale = hoverScale
    end
    
    -- Calculate the magnification offset to keep frame size constant
    if closestIndex > 0 and closestDistance < iconSize then
        local totalExtraSize = 0
        for _, icon in ipairs(visibleIcons) do
            local extraSize = (icon.targetScale - 1) * iconSize
            totalExtraSize = totalExtraSize + extraSize
        end
        
        -- Calculate where the hovered icon is relative to the center of visible icons
        local centerIndex = #visibleIcons / 2
        local offsetRatio = (closestIndex - centerIndex) / #visibleIcons
        
        targetMagOffset = totalExtraSize * offsetRatio
    else
        targetMagOffset = 0
    end
end

-- Animation for dock alpha, icon scale/alpha, and fisheye layout
local function OnAnimationUpdate(self, elapsed)
    if not dock or InCombatLockdown() then
        self:SetScript("OnUpdate", nil)
        return
    end
    
    local t = math.min(elapsed * ANIMATION_SPEED, 1)
    local needsUpdate = false
    
    -- Animate dock alpha
    if math.abs(currentDockAlpha - targetDockAlpha) > 0.001 then
        currentDockAlpha = Lerp(currentDockAlpha, targetDockAlpha, t)
        dock:SetAlpha(currentDockAlpha)
        needsUpdate = true
    end
    
    -- Recalculate icon scale/alpha targets if hovering
    if isMouseOver then
        CalculateIconTargets()
    end
    
    -- Animate magnification offset
    if math.abs(magnificationOffset - targetMagOffset) > 0.1 then
        magnificationOffset = Lerp(magnificationOffset, targetMagOffset, t)
        needsUpdate = true
    else
        magnificationOffset = targetMagOffset
    end
    
    -- Get layout settings
    local iconSize = Plugin:GetSetting(1, "IconSize") or 36
    local spacing = Plugin:GetSetting(1, "Spacing") or 4
    
    -- Animate each icon's scale and alpha, then reposition
    local currentPos = -magnificationOffset  -- Start position shifted by magnification offset
    
    for _, icon in ipairs(visibleIcons) do
        local targetScale = icon.targetScale or 1
        local targetAlpha = icon.targetAlpha or 1
        local currentScale = icon.currentScale or 1
        local currentAlpha = icon.currentAlpha or 1
        
        -- Animate scale
        if math.abs(currentScale - targetScale) > 0.001 then
            currentScale = Lerp(currentScale, targetScale, t)
            icon.currentScale = currentScale
            needsUpdate = true
        else
            icon.currentScale = targetScale
        end
        
        -- Animate alpha
        if math.abs(currentAlpha - targetAlpha) > 0.001 then
            currentAlpha = Lerp(currentAlpha, targetAlpha, t)
            icon.currentAlpha = currentAlpha
            needsUpdate = true
        else
            icon.currentAlpha = targetAlpha
        end
        
        -- Apply alpha
        icon:SetAlpha(icon.currentAlpha)
        
        -- Calculate arc offset using helper
        local maxVisible = Plugin:GetSetting(1, "MaxVisible") or 11
        maxVisible = NormalizeMaxVisible(maxVisible, #visibleIcons)
        local arcDepth = Plugin:GetSetting(1, "ArcDepth") or DEFAULT_ARC_DEPTH
        local arcOffset = CalculateArcOffset(icon.iconIndex, maxVisible, iconSize, arcDepth)
        
        -- Apply scale by RESIZING the icon (not SetScale, which causes coordinate issues)
        local scaledSize = iconSize * icon.currentScale
        icon:SetSize(scaledSize, scaledSize)
        
        -- Also resize the border to match the scaled icon
        if icon.border then
            local borderSize = scaledSize * 1.1
            icon.border:SetSize(borderSize, borderSize)
        end
        
        -- Calculate effective size using TARGET scale for stable layout
        local effectiveSize = iconSize * targetScale
        
        -- Reposition the icon based on orientation
        local posCenter = currentPos + (effectiveSize / 2)
        local iconHalfSize = scaledSize / 2
        PositionIconForOrientation(icon, dock, arcOffset, posCenter, iconHalfSize, true)
        
        -- Advance position for next icon (using TARGET scale for stable layout)
        currentPos = currentPos + effectiveSize + spacing
    end
    
    if not needsUpdate and not isMouseOver then
        self:SetScript("OnUpdate", nil)
    end
end

-- Start the animation loop
local function StartAnimation()
    if not animationFrame then
        animationFrame = CreateFrame("Frame")
    end
    animationFrame:SetScript("OnUpdate", OnAnimationUpdate)
end

-- Reset all icon scales and alphas when mouse leaves
local function ResetIconTargets()
    for _, icon in ipairs(visibleIcons) do
        icon.targetScale = 1
        icon.targetAlpha = 1
    end
    targetMagOffset = 0
end

-- Fade dock when mouse enters/leaves
local function FadeDockIn()
    targetDockAlpha = 1
    StartAnimation()
end

local function FadeDockOut()
    if not InCombatLockdown() then
        targetDockAlpha = RESTING_ALPHA
        ResetIconTargets() -- Reset icons to full scale/alpha before fading out
        StartAnimation()
    end
end

-- ============================================================================
-- ICON CREATION
-- ============================================================================

local function CreateTeleportIcon()
    local icon = CreateFrame("Button", nil, dock, "SecureActionButtonTemplate")
    icon:SetPropagateMouseClicks(true)
    icon:SetSize(36, 36)
    
    -- Circular mask for round icons
    icon.mask = icon:CreateMaskTexture()
    icon.mask:SetAllPoints()
    icon.mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    
    -- Icon texture (masked to be circular)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.texture:AddMaskTexture(icon.mask)
    
    -- Cooldown frame
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetHideCountdownNumbers(false)
    icon.cooldown:SetSwipeTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    
    -- Circular border using talent tree style ring
    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetPoint("CENTER")
    -- Atlas will be set in ConfigureIcon based on category
    -- Border will use UseAtlasSize for proper dimensions
    
    -- PreClick handler for random hearthstone - picks a new random one each click
    icon:SetScript("PreClick", function(self)
        local data = self.teleportData
        if data and data.type == "random_hearthstone" and data.availableHearthstones then
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
    
    -- Scripts
    icon:SetScript("OnEnter", function(self)
        -- On FIRST entry (when dock was not already hovered), calculate scroll position from cursor Y
        if not isMouseOver and dock then
            local maxVisible = Plugin:GetSetting(1, "MaxVisible") or 11
            local totalItems = #teleportList
            
            if totalItems > 0 then
                maxVisible = NormalizeMaxVisible(maxVisible, totalItems)
                
                -- Center slot is at maxVisible/2 (e.g., 5 for maxVisible=11)
                local centerSlot = math.floor(maxVisible / 2)
                
                -- Set scrollOffset so item 1 (Hearthstone) appears at centerSlot
                scrollOffset = (totalItems - centerSlot) % totalItems
                
                if RefreshDock then
                    RefreshDock()
                end
            end
        end
        
        isMouseOver = true
        FadeDockIn()
        
        if self.teleportData and LibQTip then
            local data = self.teleportData
            
            -- Release any existing tooltip
            if tooltip then
                LibQTip:Release(tooltip)
            end
            
            -- Create new tooltip with 2 columns
            tooltip = LibQTip:Acquire("OrbitTeleportDockTooltip", 2, "LEFT", "RIGHT")
            tooltip:SetAutoHideDelay(0.1, self)
            
            -- Position tooltip on opposite side of screen from dock
            local screenWidth = GetScreenWidth()
            local dockCenterX = dock:GetCenter()
            tooltip:ClearAllPoints()
            if dockCenterX < screenWidth / 2 then
                -- Dock is on left side, show tooltip on right
                tooltip:SetPoint("LEFT", self, "RIGHT", 10, 0)
            else
                -- Dock is on right side, show tooltip on left
                tooltip:SetPoint("RIGHT", self, "LEFT", -10, 0)
            end
            -- Line 1: Short name (large, yellow)
            local shortName = data.short or ""
            local fullName = data.name or "Unknown"
            local line
            
            if shortName ~= "" then
                line = tooltip:AddLine()
                tooltip:SetCell(line, 1, "|cffFFD100" .. shortName .. "|r", nil, "LEFT", 2)
            end
            
            -- Line 2: Full name (white)
            line = tooltip:AddLine()
            tooltip:SetCell(line, 1, "|cffFFFFFF" .. fullName .. "|r", nil, "LEFT", 2)
            
            -- Line 3: Category (gray)
            local categoryName = TD.CategoryNames[data.category] or data.category or "Teleport"
            line = tooltip:AddLine()
            tooltip:SetCell(line, 1, "|cff888888" .. categoryName .. "|r", nil, "LEFT", 2)
            
            -- For seasonal dungeons with M+ data, show rating and best run
            if data.challengeModeID and (data.category == "SEASONAL_DUNGEON") then
                tooltip:AddSeparator()
                
                -- Get M+ best run info (with pcall for secret value protection)
                local intimeInfo, overtimeInfo, bestInfo
                local dungeonScore = 0
                local mapID = data.challengeModeID
                
                -- Try to get fresh data, fall back to cache if API fails (secret values)
                local ok1, result1, result2 = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
                if ok1 then
                    intimeInfo = result1
                    overtimeInfo = result2
                    bestInfo = intimeInfo or overtimeInfo
                    -- Cache the result
                    mythicPlusCache[mapID] = mythicPlusCache[mapID] or {}
                    mythicPlusCache[mapID].bestInfo = bestInfo
                elseif mythicPlusCache[mapID] then
                    bestInfo = mythicPlusCache[mapID].bestInfo
                end
                
                -- Get per-dungeon score/rating (with pcall for secret value protection)
                local ok2, affixScores, score = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
                if ok2 then
                    dungeonScore = score or 0
                    -- Cache the result
                    mythicPlusCache[mapID] = mythicPlusCache[mapID] or {}
                    mythicPlusCache[mapID].dungeonScore = dungeonScore
                elseif mythicPlusCache[mapID] and mythicPlusCache[mapID].dungeonScore then
                    dungeonScore = mythicPlusCache[mapID].dungeonScore
                end
                
                -- Color rating based on score (approximate M+ colors)
                local ratingColor
                if dungeonScore >= 300 then
                    ratingColor = "ffFF8000" -- Orange
                elseif dungeonScore >= 250 then
                    ratingColor = "ffA335EE" -- Purple
                elseif dungeonScore >= 200 then
                    ratingColor = "ff0070DD" -- Blue
                elseif dungeonScore >= 100 then
                    ratingColor = "ff1EFF00" -- Green
                else
                    ratingColor = "ffFFFFFF" -- White
                end
                
                -- Show Rating
                line = tooltip:AddLine()
                tooltip:SetCell(line, 1, "Rating: |c" .. ratingColor .. dungeonScore .. "|r", nil, "LEFT", 2)
                
                if bestInfo then
                    -- Show Best Run header
                    line = tooltip:AddLine()
                    tooltip:SetCell(line, 1, " ")  -- Empty line for spacing
                    
                    line = tooltip:AddLine()
                    tooltip:SetCell(line, 1, "|cff00FF00Best Run|r", nil, "LEFT", 2)
                    
                    -- Show level and time on same line
                    line = tooltip:AddLine()
                    
                    -- Safely access bestInfo fields (may be secret)
                    local level, durationSec
                    local ok3, _ = pcall(function()
                        level = bestInfo.level
                        durationSec = bestInfo.durationSec
                    end)
                    
                    if ok3 and level and durationSec then
                        tooltip:SetCell(line, 1, "Level " .. level)
                        -- Format time
                        local mins = math.floor(durationSec / 60)
                        local secs = durationSec % 60
                        local timeText = string.format("%d:%02d", mins, secs)
                        tooltip:SetCell(line, 2, timeText)
                        
                        -- Cache this too
                        mythicPlusCache[mapID].level = level
                        mythicPlusCache[mapID].durationSec = durationSec
                    elseif mythicPlusCache[mapID] and mythicPlusCache[mapID].level then
                        -- Use cached data
                        tooltip:SetCell(line, 1, "Level " .. mythicPlusCache[mapID].level)
                        local mins = math.floor(mythicPlusCache[mapID].durationSec / 60)
                        local secs = mythicPlusCache[mapID].durationSec % 60
                        tooltip:SetCell(line, 2, string.format("%d:%02d", mins, secs))
                    end
                else
                    -- No run data
                    line = tooltip:AddLine()
                    tooltip:SetCell(line, 1, "|cff888888No best run yet|r", nil, "LEFT", 2)
                end
            end
            
            -- Add cooldown info if available
            if data.cooldown and data.cooldown > 0 then
                tooltip:AddSeparator()
                local hours = math.floor(data.cooldown / 3600)
                local mins = math.floor((data.cooldown % 3600) / 60)
                local cooldownText
                if hours > 0 then
                    cooldownText = string.format("%dh %dm", hours, mins)
                else
                    cooldownText = string.format("%dm", mins)
                end
                line = tooltip:AddLine()
                tooltip:SetCell(line, 1, "|cffFF6666" .. cooldownText .. " cooldown|r", nil, "LEFT", 2)
            end
            
            tooltip:Show()
        else
            -- Fallback to GameTooltip if LibQTip not available
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.teleportData then
                local data = self.teleportData
                if data.type == "spell" then
                    GameTooltip:SetSpellByID(data.spellID)
                elseif data.type == "toy" or data.type == "item" then
                    GameTooltip:SetToyByItemID(data.itemID)
                end
            end
            GameTooltip:Show()
        end
    end)
    
    icon:SetScript("OnLeave", function(self)
        -- LibQTip auto-hides via SetAutoHideDelay, but we also hide GameTooltip as fallback
        GameTooltip:Hide()
        
        -- Check if mouse left the dock entirely (not just moved to another icon)
        if dock and not dock:IsMouseOver() then
            isMouseOver = false
            -- Reset scrollOffset to center the first item (Hearthstone) on next hover
            local maxVisible = Plugin:GetSetting(1, "MaxVisible") or 11
            local totalItems = #teleportList
            if totalItems > 0 then
                maxVisible = NormalizeMaxVisible(maxVisible, totalItems)
                local centerSlot = math.floor(maxVisible / 2)
                scrollOffset = (totalItems - centerSlot) % totalItems
            else
                scrollOffset = 0
            end
            ResetIconTargets()
            FadeDockOut()
        end
    end)
    
    return icon
end



-- ============================================================================
-- ICON CONFIGURATION
-- ============================================================================

local function ConfigureIcon(icon, data, index)
    icon.teleportData = data
    icon.iconIndex = index
    icon.type = data.type
    
    local iconSize = Plugin:GetSetting(1, "IconSize") or 36
    icon:SetSize(iconSize, iconSize)
    
    -- Size the border to match icon size (we'll scale it after setting atlas)
    local borderSize = iconSize * 1.1  -- Slightly larger than icon for ring effect
    
    -- Set border atlas based on category
    local category = data.category
    if category == "SEASONAL_DUNGEON" or category == "SEASONAL_RAID" then
        -- Golden ring for current season content
        icon.border:SetAtlas("talents-node-circle-yellow", false)  -- false = don't use atlas size
    else
        -- Gray ring for everything else
        icon.border:SetAtlas("talents-node-circle-gray", false)
    end
    icon.border:SetSize(borderSize, borderSize)
    
    if data.icon then
        icon.texture:SetTexture(data.icon)
    else
        icon.texture:SetTexture(134400)
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
        end
    end
    
    -- Check if cooldowns should be shown
    local showCooldowns = Plugin:GetSetting(1, "ShowCooldowns")
    if showCooldowns == nil then showCooldowns = true end
    
    if showCooldowns and data.cooldown and data.cooldown > 0 then
        local startTime = GetTime() - (data.cooldown or 0)
        icon.cooldown:SetCooldown(startTime, data.cooldown)
        icon.cooldown:Show()
    else
        icon.cooldown:Clear()
        icon.cooldown:Hide()
    end
    
    -- Initialize animation state
    icon.currentScale = 1
    icon.currentAlpha = 1
    icon.targetScale = 1
    icon.targetAlpha = 1
    icon:SetAlpha(1)
    icon:Show()
end

-- ============================================================================
-- DOCK LAYOUT - Arc/Curve with Infinite Scroll
-- ============================================================================

-- Assign to forward-declared variable so OnEnter can call it
RefreshDock = function()
    if not dock or not CanInteract() then return end
    
    -- Hide all current icons
    for _, icon in ipairs(visibleIcons) do
        icon:Hide()
        icon:ClearAllPoints()
    end
    wipe(visibleIcons)
    
    -- Get fresh teleport list (filtered - no dividers from scanner)
    teleportList = Scanner:GetOrderedList()
    local totalItems = #teleportList
    
    if totalItems == 0 then
        dock:Hide()
        return
    end
    
    local iconSize = Plugin:GetSetting(1, "IconSize") or 36
    local spacing = Plugin:GetSetting(1, "Spacing") or 4
    local maxVisible = Plugin:GetSetting(1, "MaxVisible") or 11
    
    -- Detect and update orientation based on dock position
    currentOrientation = DetectOrientation()
    
    -- Normalize maxVisible using helper
    maxVisible = NormalizeMaxVisible(maxVisible, totalItems)
    
    -- Show exactly maxVisible icons (equal above and below center)
    local currentPos = 0  -- Position along the layout direction
    local iconPoolIndex = 0
    local arcDepth = Plugin:GetSetting(1, "ArcDepth") or DEFAULT_ARC_DEPTH
    
    for displayIndex = 0, maxVisible - 1 do
        iconPoolIndex = iconPoolIndex + 1
        
        -- INFINITE SCROLL: Wrap around using modulo
        local actualIndex = ((scrollOffset + displayIndex) % totalItems) + 1
        local data = teleportList[actualIndex]
        
        if data then
            -- Get or create icon from pool
            if not iconPool then
                iconPool = {}
            end
            local icon = iconPool[iconPoolIndex]
            if not icon then
                icon = CreateTeleportIcon()
                table.insert(iconPool, icon)
            end
            
            ConfigureIcon(icon, data, displayIndex)
            
            -- Calculate arc offset using helper
            local arcOffset = CalculateArcOffset(displayIndex, maxVisible, iconSize, arcDepth)
            
            -- Position icon using helper
            PositionIconForOrientation(icon, dock, arcOffset, currentPos, 0, false)
            
            currentPos = currentPos + iconSize + spacing
            
            table.insert(visibleIcons, icon)
        end
    end
    
    -- Update dock size based on orientation
    local arcDepth = Plugin:GetSetting(1, "ArcDepth") or DEFAULT_ARC_DEPTH
    local dockLength = math.max(currentPos - spacing, iconSize)
    local dockThickness = iconSize + arcDepth + 10
    
    if IsHorizontal() then
        dock:SetWidth(dockLength)
        dock:SetHeight(dockThickness)
    else
        dock:SetWidth(dockThickness)
        dock:SetHeight(dockLength)
    end
    
    dock:Show()
end

-- ============================================================================
-- SCROLL HANDLING - Infinite Scroll
-- ============================================================================

local function OnMouseWheel(self, delta)
    if not CanInteract() then return end
    
    local totalIcons = #teleportList
    if totalIcons == 0 then return end
    
    -- INFINITE SCROLL: Wrap around
    scrollOffset = (scrollOffset - delta) % totalIcons
    
    RefreshDock()
end

-- ============================================================================
-- DOCK CREATION
-- ============================================================================

local function CreateDock()
    dock = CreateFrame("Frame", "OrbitTeleportDock", UIParent)
    dock:SetSize(44, 200)
    dock:SetPoint("LEFT", UIParent, "LEFT", 10, 0)
    dock:SetFrameStrata("MEDIUM")
    dock:SetFrameLevel(100)
    dock:SetClampedToScreen(true)
    dock:EnableMouse(true)
    dock:SetMovable(true)
    dock:RegisterForDrag("LeftButton")
    
    -- No backdrop - dock is purely icons and dividers
    -- Edit Mode selection highlight is provided by Orbit's Selection overlay
    
    -- Note: Drag handling is managed by Orbit's Selection system (AttachSettingsListener)
    -- The Selection overlay intercepts clicks and handles dragging through EditModeSystemSelectionTemplate
    
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
    
    -- Edit mode orientation tracking: update orientation in real-time while dragging
    local lastOrientation = currentOrientation
    dock:HookScript("OnUpdate", function(self)
        -- Only track during edit mode
        if not EditModeManagerFrame or not EditModeManagerFrame:IsShown() then
            return
        end
        
        -- Check if orientation has changed
        local newOrientation = DetectOrientation()
        if newOrientation ~= lastOrientation then
            lastOrientation = newOrientation
            currentOrientation = newOrientation
            -- Refresh layout with new orientation (safe because not in combat during edit mode)
            RefreshDock()
        end
    end)
    
    return dock
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function Plugin:OnLoad()
    -- Create the dock frame
    dock = CreateDock()
    self.frame = dock
    
    -- Register for Edit Mode selection and settings
    dock.editModeName = "Teleport Dock"
    dock.systemIndex = 1
    dock.orbitNoSnap = true  -- Disable anchoring/snapping to other frames
    
    -- Attach to Orbit's Edit Mode selection system (enables highlight + settings panel)
    if OrbitEngine and OrbitEngine.Frame then
        OrbitEngine.Frame:AttachSettingsListener(dock, self, 1)
        
        -- If Edit Mode is already active (plugin loaded mid-session), show selection
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            if OrbitEngine.FrameSelection then
                dock:SetMovable(true)
                OrbitEngine.FrameSelection:UpdateVisuals(dock)
            end
        end
    end
    
    -- Restore saved position using Orbit's position system
    if OrbitEngine and OrbitEngine.Frame then
        OrbitEngine.Frame:RestorePosition(dock, self, 1)
    else
        -- Fallback: Load saved position manually
        local pos = self:GetSetting(1, "Position")
        if pos then
            dock:ClearAllPoints()
            dock:SetPoint(pos.point or "LEFT", UIParent, pos.relPoint or "LEFT", pos.x or 10, pos.y or 0)
        end
    end
    
    -- Event handling for combat state (stored on Plugin for cleanup)
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("SPELLS_CHANGED")
    self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    
    self.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if CanInteract() then
                UpdateCombatState()
                RefreshDock()
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            UpdateCombatState()
        elseif event == "ENCOUNTER_START" then
            UpdateCombatState()
        elseif event == "ENCOUNTER_END" then
            if not InCombatLockdown() then
                UpdateCombatState()
                RefreshDock()
            end
        elseif event == "SPELLS_CHANGED" or event == "BAG_UPDATE_DELAYED" then
            if CanInteract() then
                RefreshDock()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(1, function()
                if CanInteract() then
                    RefreshDock()
                end
            end)
        end
    end)
    
    -- Cooldown refresh timer (with race condition guard)
    self.cooldownTicker = C_Timer.NewTicker(5, function()
        if dock and dock:IsShown() and not InCombatLockdown() then
            -- Take snapshot to prevent race condition during iteration
            local iconSnapshot = {}
            for i, icon in ipairs(visibleIcons) do
                iconSnapshot[i] = icon
            end
            
            Scanner:RefreshCooldowns(teleportList)
            
            for _, icon in ipairs(iconSnapshot) do
                if icon and icon.teleportData and icon.cooldown then
                    local data = icon.teleportData
                    if data.cooldown and data.cooldown > 0 then
                        icon.cooldown:SetCooldown(GetTime() - data.cooldown, data.cooldown)
                    else
                        icon.cooldown:Clear()
                    end
                end
            end
        end
    end)
    
    self:RegisterStandardEvents()
    
    -- Track Edit Mode state for disabling secure actions
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            if not InCombatLockdown() then
                isEditModeActive = true
                RefreshDock() -- Re-configure icons with Edit Mode awareness
            end
        end, self)
        
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            if not InCombatLockdown() then
                isEditModeActive = false
                RefreshDock() -- Restore secure actions
            end
        end, self)
    end
end

function Plugin:ApplySettings()
    if not dock then return end
    RefreshDock()
end

function Plugin:OnUnload()
    -- Release tooltip to prevent memory leak
    if tooltip and LibQTip then
        LibQTip:Release(tooltip)
        tooltip = nil
    end
    
    -- Cancel cooldown ticker
    if self.cooldownTicker then
        self.cooldownTicker:Cancel()
        self.cooldownTicker = nil
    end
end

-- ============================================================================
-- SETTINGS UI
-- ============================================================================

function Plugin:AddSettings(dialog, systemFrame)
    local schema = {
        controls = {
            { type = "checkbox", key = "ShowCooldowns", label = "Show Cooldowns", default = true },
            { type = "slider", key = "IconSize", label = "Icon Size", min = 24, max = 40, step = 2, default = 36 },
            { type = "slider", key = "Spacing", label = "Icon Padding", min = 0, max = 20, step = 1, default = 4 },
            { type = "slider", key = "MaxVisible", label = "Max Visible Icons", min = 3, max = 21, step = 2, default = 11 },
            { type = "slider", key = "ArcDepth", label = "Arc Depth", min = 0, max = 30, step = 1, default = 5 },
            { type = "slider", key = "HoverScale", label = "Magnification Scale", min = 1.0, max = 2.0, step = 0.05, default = 1.33 },
        },
    }
    
    Orbit.Config:Render(dialog, systemFrame, self, schema)
end

-- Export for debugging
addon.TeleportDock = Plugin

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_ORBITTELEPORT1 = "/teleport"
SLASH_ORBITTELEPORT2 = "/tp"
SlashCmdList["ORBITTELEPORT"] = function(msg)
    local cmd = msg:lower():trim()
    
    if cmd == "scan" then
        -- Clear M+ cache and force refresh
        wipe(mythicPlusCache)
        if CanInteract() then
            RefreshDock()
        end
        print("|cff00ff00[Orbit Teleport]|r M+ cache cleared and dock refreshed!")
    elseif cmd == "refresh" then
        -- Just refresh the dock
        if CanInteract() then
            RefreshDock()
        end
        print("|cff00ff00[Orbit Teleport]|r Dock refreshed!")
    elseif cmd == "debug" then
        -- Print all challenge mode dungeon IDs (useful for finding correct IDs)
        print("|cff00ff00[Orbit Teleport]|r Challenge Mode Dungeons:")
        for i = 1, 700 do
            local name = C_ChallengeMode.GetMapUIInfo(i)
            if name then
                print("  ID: " .. i .. " - " .. name)
            end
        end
    else
        print("|cff00ff00[Orbit Teleport]|r Commands:")
        print("  /orbit scan - Clear M+ cache and refresh dock")
        print("  /orbit refresh - Refresh dock")
        print("  /orbit debug - List all challenge mode IDs")
    end
end
