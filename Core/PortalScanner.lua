-- PortalScanner.lua
-- Runtime scanner to detect available portals for the current character

local _, addon = ...
addon.PortalScanner = {}

local Scanner = addon.PortalScanner
local PD = addon.PortalData

-- Cache player info
local playerClass = select(2, UnitClass("player"))
local playerFaction = UnitFactionGroup("player")

-- Cache for async housing data
local cachedHouseList = nil

-- ============================================================================
-- DETECTION FUNCTIONS
-- ============================================================================

-- Check if a spell is known
local function IsSpellAvailable(spellID)
    return C_SpellBook.IsSpellKnown(spellID)
end

-- Check if a toy is owned
local function IsToyOwned(itemID)
    return PlayerHasToy and PlayerHasToy(itemID)
end

-- Check if a toy is usable (owned AND can be used in current zone)
local function IsToyUsable(itemID)
    if not PlayerHasToy or not PlayerHasToy(itemID) then
        return false
    end
    -- C_ToyBox.IsToyUsable checks zone restrictions, level requirements, etc.
    return C_ToyBox and C_ToyBox.IsToyUsable and C_ToyBox.IsToyUsable(itemID)
end


-- Check if player has an item in bags
local function HasItem(itemID)
    return C_Item.GetItemCount(itemID) > 0
end

-- Check faction requirement
local function MeetsFactionRequirement(data)
    if not data.faction then return true end
    return data.faction == playerFaction
end

-- Check class requirement
local function MeetsClassRequirement(data)
    if not data.class then return true end
    return data.class == playerClass
end

-- Get spell/item cooldown info
local function GetCooldownInfo(isSpell, id)
    if not id then return 0, 0 end
    
    local startTime, duration
    
    if isSpell then
        local ok, cooldownInfo = pcall(C_Spell.GetSpellCooldown, id)
        if ok and cooldownInfo then
            startTime = cooldownInfo.startTime
            duration = cooldownInfo.duration
        end
    else
        local ok, st, dur = pcall(C_Container.GetItemCooldown, id)
        if ok then
            startTime = st
            duration = dur
        end
    end
    
    -- Use pcall to safely compare values (may be "secret" during encounters)
    local ok, remaining = pcall(function()
        if startTime and duration and startTime > 0 then
            local rem = (startTime + duration) - GetTime()
            return rem > 0 and rem or 0
        end
        return 0
    end)
    
    if ok then
        return remaining, duration or 0
    end
    
    return 0, 0
end

-- Get spell info (name, icon)
local function GetSpellDetails(spellID)
    local info = C_Spell.GetSpellInfo(spellID)
    if info then
        return info.name, info.iconID
    end
    return nil, nil
end

-- Get item info (name, icon) - uses GetItemInfoInstant for immediate results
local function GetItemDetails(itemID)
    -- GetItemInfoInstant returns immediately (synchronous) - use for icon
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
    -- GetItemInfo may return nil if item isn't cached - use for name with fallback
    local name = C_Item.GetItemInfo(itemID)
    -- If name isn't cached yet, use "Item #ID" as placeholder
    if not name then
        name = "Item " .. itemID
    end
    return name, icon
end

-- ============================================================================
-- CATEGORY SCANNERS
-- ============================================================================

-- Generic dungeon scanner for any expansion category
function Scanner:ScanDungeonCategory(categoryData, categoryName)
    local results = {}
    
    for _, data in ipairs(categoryData or {}) do
        -- Check faction requirement
        if MeetsFactionRequirement(data) then
            if IsSpellAvailable(data.spellID) then
                local spellName, icon = GetSpellDetails(data.spellID)
                if spellName then
                    local cooldown, cooldownDuration = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = spellName,  -- Portal spell name
                        instanceName = data.name,  -- Dungeon/instance name from PortalData
                        short = data.short,
                        challengeModeID = data.challengeModeID,
                        icon = icon,
                        cooldown = cooldown,
                        cooldownDuration = cooldownDuration,
                        category = categoryName,
                    })
                end
            end
        end
    end
    
    return results
end

-- Scan for current season dungeons (pulls from expansion categories but filters by season list)
function Scanner:ScanSeasonalDungeons()
    local results = {}
    local seasonalSpells = {}
    
    -- Build lookup table for seasonal dungeons
    for _, spellID in ipairs(PD.CURRENT_SEASON_DUNGEONS) do
        seasonalSpells[spellID] = true
    end
    
    -- Check all expansion dungeon categories for seasonal dungeons
    local dungeonCategories = {
        PD.TWW_DUNGEON,
        PD.DF_DUNGEON,
        PD.SL_DUNGEON,
        PD.BFA_DUNGEON,
        PD.LEGION_DUNGEON,
        PD.WOD_DUNGEON,
        PD.MOP_DUNGEON,
        PD.CATA_DUNGEON,
        PD.CLASSIC_DUNGEON,
    }
    
    for _, categoryData in ipairs(dungeonCategories) do
        for _, data in ipairs(categoryData or {}) do
            if seasonalSpells[data.spellID] and MeetsFactionRequirement(data) then
                if IsSpellAvailable(data.spellID) then
                    local spellName, icon = GetSpellDetails(data.spellID)
                    if spellName then
                        local cooldown, cooldownDuration = GetCooldownInfo(true, data.spellID)
                        table.insert(results, {
                            type = "spell",
                            spellID = data.spellID,
                            name = spellName,  -- Portal spell name
                            instanceName = data.name,  -- Dungeon/instance name from PortalData
                            short = data.short,
                            challengeModeID = data.challengeModeID,
                            icon = icon,
                            cooldown = cooldown,
                            cooldownDuration = cooldownDuration,
                            category = "SEASONAL_DUNGEON",
                        })
                    end
                end
            end
        end
    end
    
    return results
end

-- Scan for current season raids
function Scanner:ScanSeasonalRaids()
    local results = {}
    local seasonalSpells = {}
    
    for _, spellID in ipairs(PD.CURRENT_SEASON_RAIDS) do
        seasonalSpells[spellID] = true
    end
    
    local raidCategories = { PD.TWW_RAID, PD.DF_RAID, PD.SL_RAID }
    
    for _, categoryData in ipairs(raidCategories) do
        for _, data in ipairs(categoryData or {}) do
            if seasonalSpells[data.spellID] then
                if IsSpellAvailable(data.spellID) then
                    local spellName, icon = GetSpellDetails(data.spellID)
                    if spellName then
                        local cooldown, cooldownDuration = GetCooldownInfo(true, data.spellID)
                        table.insert(results, {
                            type = "spell",
                            spellID = data.spellID,
                            name = spellName,  -- Portal spell name
                            instanceName = data.name,  -- Raid/instance name from PortalData
                            short = data.short,
                            icon = icon,
                            cooldown = cooldown,
                            cooldownDuration = cooldownDuration,
                            category = "SEASONAL_RAID",
                        })
                    end
                end
            end
        end
    end
    
    return results
end

-- Returns ONE unified hearthstone entry that casts a random available hearthstone on click
function Scanner:ScanHearthstones()
    local results = {}
    local allAvailable = {}
    
    -- Collect all available shared-cooldown hearthstones
    for _, data in ipairs(PD.HEARTHSTONE_SHARED or {}) do
        local available = false
        local name, icon
        
        if data.type == "toy" then
            available = IsToyOwned(data.itemID)
            if available then
                name, icon = GetItemDetails(data.itemID)
            end
        elseif data.type == "item" then
            available = HasItem(data.itemID)
            if available then
                name, icon = GetItemDetails(data.itemID)
            end
        end
        
        if available and name then
            table.insert(allAvailable, {
                type = data.type == "toy" and "toy" or "item",
                itemID = data.itemID,
                name = name or data.name,
                icon = icon,
            })
        end
    end
    
    -- If we have any hearthstones, create ONE unified entry
    if #allAvailable > 0 then
        -- Get cooldown from first available (they share cooldown)
        local cooldown, cooldownDuration = GetCooldownInfo(false, allAvailable[1].itemID)
        
        -- Get icon from base hearthstone item (6948)
        local _, _, _, _, hearthIcon = C_Item.GetItemInfoInstant(6948)
        
        table.insert(results, {
            type = "random_hearthstone",  -- Special type for PortalDock to handle
            name = "Hearthstone",
            short = "HS",
            icon = hearthIcon or 134414,  -- Fallback to common hearth icon
            cooldown = cooldown,
            cooldownDuration = cooldownDuration,
            category = "HEARTHSTONE",
            availableHearthstones = allAvailable,  -- Store all options for random selection
        })
    end
    
    -- Add all unique cooldown hearthstones (these are separate, not randomized)
    for _, data in ipairs(PD.HEARTHSTONE_UNIQUE or {}) do
        local available = false
        local name, icon
        
        if data.type == "toy" then
            available = IsToyOwned(data.itemID)
            if available then
                name, icon = GetItemDetails(data.itemID)
            end
        elseif data.type == "item" then
            available = HasItem(data.itemID)
            if available then
                name, icon = GetItemDetails(data.itemID)
            end
        end
        
        if available then
            local cooldown, cooldownDuration = GetCooldownInfo(false, data.itemID)
            table.insert(results, {
                type = data.type,  -- Preserve original type (toy or item)
                itemID = data.itemID,
                name = name or data.name,
                icon = icon,
                cooldown = cooldown,
                cooldownDuration = cooldownDuration,
                category = "HEARTHSTONE",
            })
        end
    end
    
    return results
end

function Scanner:ScanClassSpells()
    local results = {}
    
    for _, data in ipairs(PD.CLASS or {}) do
        if MeetsClassRequirement(data) then
            if IsSpellAvailable(data.spellID) then
                local name, icon = GetSpellDetails(data.spellID)
                if name then
                    local cooldown = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        category = "CLASS",
                    })
                end
            end
        end
    end
    
    return results
end

function Scanner:ScanMageTeleports()
    local results = {}
    
    if playerClass ~= "MAGE" then return results end
    
    for _, data in ipairs(PD.MAGE_TELEPORT or {}) do
        if MeetsFactionRequirement(data) then
            if IsSpellAvailable(data.spellID) then
                local name, icon = GetSpellDetails(data.spellID)
                if name then
                    local cooldown = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        category = "MAGE_TELEPORT",
                    })
                end
            end
        end
    end
    
    return results
end

function Scanner:ScanMagePortals()
    local results = {}
    
    if playerClass ~= "MAGE" then return results end
    
    for _, data in ipairs(PD.MAGE_PORTAL or {}) do
        if MeetsFactionRequirement(data) then
            if IsSpellAvailable(data.spellID) then
                local name, icon = GetSpellDetails(data.spellID)
                if name then
                    local cooldown = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        category = "MAGE_PORTAL",
                        isPortal = true,
                    })
                end
            end
        end
    end
    
    return results
end

function Scanner:ScanToys()
    local results = {}
    
    for _, data in ipairs(PD.TOY or {}) do
        if MeetsFactionRequirement(data) then
            local itemID = data.itemID
            local available = false
            local name, icon
            
            if data.type == "item" then
                available = HasItem(itemID)
            else
                -- Use IsToyUsable to filter out toys that can't be used in current zone
                available = IsToyUsable(itemID)
            end
            
            if available then
                name, icon = GetItemDetails(itemID)
                if name then
                    local cooldown = GetCooldownInfo(false, itemID)
                    table.insert(results, {
                        type = data.type or "toy",
                        itemID = itemID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        category = "TOY",
                        destination = data.destination,
                    })
                end
            end
        end
    end
    
    return results
end

function Scanner:ScanEngineeringSpells()
    local results = {}
    
    -- Check if player has engineering profession
    local hasEngineering = false
    local rank = 0
    local professions = { GetProfessions() }
    for _, profIndex in pairs(professions) do
        if profIndex then
            local name, _, skillRank, _, _, _, skillLineID = GetProfessionInfo(profIndex)
            -- Use skill line ID 202 (Engineering) for locale-independent detection
            if skillLineID == 202 then
                hasEngineering = true
                rank = skillRank
                break
            end
        end
    end
    
    if not hasEngineering then
        return results
    end
    
    for _, data in ipairs(PD.ENGINEER or {}) do
        if MeetsFactionRequirement(data) and (not data.reqSkill or rank >= data.reqSkill) then
            local available = false
            local name, icon
            local itemID = data.itemID
            
            if data.type == "toy" then
                -- Use IsToyUsable to filter out toys that can't be used in current zone
                available = IsToyUsable(itemID)
            elseif data.type == "item" then
                available = HasItem(itemID)
            end
            
            if available then
                name, icon = GetItemDetails(itemID)
                if name then
                    local cooldown = GetCooldownInfo(false, itemID)
                    table.insert(results, {
                        type = data.type or "toy",
                        itemID = itemID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        category = "ENGINEER",
                    })
                end
            end
        end
    end
    
    return results
end

-- Scan for Player Housing teleport
function Scanner:ScanHousing()
    local results = {}
    
    -- Check if housing API is available
    if not C_Housing or not C_Housing.TeleportHome then
        return results
    end
    
    -- Try multiple detection methods (in order of reliability):
    -- 1. Cached house list from async PLAYER_HOUSE_LIST_UPDATED event
    -- 2. GetTrackedHouseGuid (may return tracked house synchronously)
    -- 3. If player is level 80+ and C_Housing exists, assume they can access housing
    
    local hasHouse = false
    local houseInfo = nil
    local displayName = "Teleport to Plot"
    local neighborhoodName = nil
    
    -- Method 1: Check cached house list
    if cachedHouseList and #cachedHouseList > 0 then
        hasHouse = true
        houseInfo = cachedHouseList[1]
        displayName = houseInfo.houseName or houseInfo.neighborhoodName or "My Plot"
        neighborhoodName = houseInfo.neighborhoodName
    end
    
    -- Method 2: Check tracked house (synchronous)
    if not hasHouse and C_Housing.GetTrackedHouseGuid then
        local trackedGuid = C_Housing.GetTrackedHouseGuid()
        if trackedGuid then
            hasHouse = true
            displayName = "My Plot"
        end
    end
    
    -- Method 3: Level 80+ with Housing API available = can likely use housing
    -- The macro will handle the actual teleport; if no house, nothing happens
    if not hasHouse then
        local level = UnitLevel("player")
        if level and level >= 80 then
            hasHouse = true
            displayName = "Teleport to Plot"
        end
    end
    
    if not hasHouse then
        return results
    end
    
    -- Get cooldown info (if available)
    local cooldown, cooldownDuration = 0, 0
    local ok, cdInfo = pcall(function()
        return C_Housing.GetVisitCooldownInfo and C_Housing.GetVisitCooldownInfo()
    end)
    if ok and cdInfo and cdInfo.startTime and cdInfo.duration then
        local remaining = (cdInfo.startTime + cdInfo.duration) - GetTime()
        cooldown = remaining > 0 and remaining or 0
        cooldownDuration = cdInfo.duration
    end
    
    table.insert(results, {
        type = "housing",
        name = displayName,
        instanceName = neighborhoodName,
        short = "HOME",
        iconAtlas = "dashboard-panel-homestone-teleport-button",  -- Blizzard's housing teleport icon
        cooldown = cooldown,
        cooldownDuration = cooldownDuration,
        category = "HOUSING",
        houseInfo = houseInfo,
    })
    
    return results
end

-- Update cached house list (called when PLAYER_HOUSE_LIST_UPDATED fires)
function Scanner:UpdateHousingCache(houseInfos)
    cachedHouseList = houseInfos
end

-- Request housing data (triggers async response via PLAYER_HOUSE_LIST_UPDATED)
function Scanner:RequestHousingData()
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        C_Housing.GetPlayerOwnedHouses()
    end
end

-- ============================================================================
-- MAIN SCAN FUNCTION
-- ============================================================================

function Scanner:ScanAll()
    local allPortals = {}
    
    -- Scan seasonal content first (highest priority)
    allPortals.SEASONAL_DUNGEON = self:ScanSeasonalDungeons()
    allPortals.SEASONAL_RAID = self:ScanSeasonalRaids()
    
    -- Hearthstones (deduplicated)
    allPortals.HEARTHSTONE = self:ScanHearthstones()
    
    -- Player Housing teleport
    allPortals.HOUSING = self:ScanHousing()
    
    -- Class portals
    allPortals.CLASS = self:ScanClassSpells()
    
    -- Mage spells (separated)
    allPortals.MAGE_TELEPORT = self:ScanMageTeleports()
    allPortals.MAGE_PORTAL = self:ScanMagePortals()
    
    -- Build set of seasonal spells to exclude from expansion categories
    local seasonalSpells = {}
    for _, spellID in ipairs(PD.CURRENT_SEASON_DUNGEONS) do
        seasonalSpells[spellID] = true
    end
    for _, spellID in ipairs(PD.CURRENT_SEASON_RAIDS) do
        seasonalSpells[spellID] = true
    end
    
    -- Expansion dungeons (excluding seasonal)
    local function filterSeasonal(results)
        local filtered = {}
        for _, item in ipairs(results) do
            if not seasonalSpells[item.spellID] then
                table.insert(filtered, item)
            end
        end
        return filtered
    end
    
    allPortals.TWW_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.TWW_DUNGEON, "TWW_DUNGEON"))
    allPortals.TWW_RAID = filterSeasonal(self:ScanDungeonCategory(PD.TWW_RAID, "TWW_RAID"))
    allPortals.DF_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.DF_DUNGEON, "DF_DUNGEON"))
    allPortals.DF_RAID = filterSeasonal(self:ScanDungeonCategory(PD.DF_RAID, "DF_RAID"))
    allPortals.SL_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.SL_DUNGEON, "SL_DUNGEON"))
    allPortals.SL_RAID = filterSeasonal(self:ScanDungeonCategory(PD.SL_RAID, "SL_RAID"))
    allPortals.BFA_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.BFA_DUNGEON, "BFA_DUNGEON"))
    allPortals.LEGION_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.LEGION_DUNGEON, "LEGION_DUNGEON"))
    allPortals.WOD_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.WOD_DUNGEON, "WOD_DUNGEON"))
    allPortals.MOP_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.MOP_DUNGEON, "MOP_DUNGEON"))
    allPortals.CATA_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.CATA_DUNGEON, "CATA_DUNGEON"))
    allPortals.CLASSIC_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.CLASSIC_DUNGEON, "CLASSIC_DUNGEON"))
    
    -- Engineering and toys
    allPortals.ENGINEER = self:ScanEngineeringSpells()
    allPortals.TOY = self:ScanToys()
    
    return allPortals
end

-- Returns flattened list with category order preserved (no dividers)
function Scanner:GetOrderedList()
    local allByCategory = self:ScanAll()
    local ordered = {}
    
    for _, category in ipairs(PD.CategoryOrder) do
        local items = allByCategory[category]
        if items and #items > 0 then
            -- Add items directly (no dividers), set category on each
            for _, item in ipairs(items) do
                item.category = category  -- Set category for tooltip
                table.insert(ordered, item)
            end
        end
    end
    
    return ordered
end

-- Refresh cooldowns for existing list (cheaper than full rescan)
function Scanner:RefreshCooldowns(portalList)
    for _, item in ipairs(portalList) do
        if item.type == "random_hearthstone" then
            -- For random hearthstone, get cooldown from first available hearthstone
            if item.availableHearthstones and #item.availableHearthstones > 0 then
                item.cooldown, item.cooldownDuration = GetCooldownInfo(false, item.availableHearthstones[1].itemID)
            end
        else
            local isSpell = item.type == "spell"
            local id = isSpell and item.spellID or item.itemID
            if id then
                item.cooldown, item.cooldownDuration = GetCooldownInfo(isSpell, id)
            end
        end
    end
end
