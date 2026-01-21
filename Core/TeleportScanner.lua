-- TeleportScanner.lua
-- Runtime scanner to detect available teleports for the current character

local _, addon = ...
addon.TeleportScanner = {}

local Scanner = addon.TeleportScanner
local TD = addon.TeleportData

-- Cache player info
local playerClass = select(2, UnitClass("player"))
local playerFaction = UnitFactionGroup("player")

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

-- Get item info (name, icon)
local function GetItemDetails(itemID)
    local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
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
                local name, icon = GetSpellDetails(data.spellID)
                if name then
                    local cooldown = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = name or data.name,
                        short = data.short,
                        challengeModeID = data.challengeModeID,
                        icon = icon,
                        cooldown = cooldown,
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
    for _, spellID in ipairs(TD.CURRENT_SEASON_DUNGEONS) do
        seasonalSpells[spellID] = true
    end
    
    -- Check all expansion dungeon categories for seasonal dungeons
    local dungeonCategories = {
        TD.TWW_DUNGEON,
        TD.DF_DUNGEON,
        TD.SL_DUNGEON,
        TD.BFA_DUNGEON,
        TD.LEGION_DUNGEON,
        TD.WOD_DUNGEON,
        TD.MOP_DUNGEON,
        TD.CATA_DUNGEON,
        TD.CLASSIC_DUNGEON,
    }
    
    for _, categoryData in ipairs(dungeonCategories) do
        for _, data in ipairs(categoryData or {}) do
            if seasonalSpells[data.spellID] and MeetsFactionRequirement(data) then
                if IsSpellAvailable(data.spellID) then
                    local name, icon = GetSpellDetails(data.spellID)
                    if name then
                        local cooldown = GetCooldownInfo(true, data.spellID)
                        table.insert(results, {
                            type = "spell",
                            spellID = data.spellID,
                            name = name or data.name,
                            short = data.short,
                            challengeModeID = data.challengeModeID,
                            icon = icon,
                            cooldown = cooldown,
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
    
    for _, spellID in ipairs(TD.CURRENT_SEASON_RAIDS) do
        seasonalSpells[spellID] = true
    end
    
    local raidCategories = { TD.TWW_RAID, TD.DF_RAID, TD.SL_RAID }
    
    for _, categoryData in ipairs(raidCategories) do
        for _, data in ipairs(categoryData or {}) do
            if seasonalSpells[data.spellID] then
                if IsSpellAvailable(data.spellID) then
                    local name, icon = GetSpellDetails(data.spellID)
                    if name then
                        local cooldown = GetCooldownInfo(true, data.spellID)
                        table.insert(results, {
                            type = "spell",
                            spellID = data.spellID,
                            name = name or data.name,
                            short = data.short,
                            icon = icon,
                            cooldown = cooldown,
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
    for _, data in ipairs(TD.HEARTHSTONE_SHARED or {}) do
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
        local cooldown = GetCooldownInfo(false, allAvailable[1].itemID)
        
        -- Get icon from base hearthstone item (6948)
        local _, _, _, _, hearthIcon = C_Item.GetItemInfoInstant(6948)
        
        table.insert(results, {
            type = "random_hearthstone",  -- Special type for TeleportDock to handle
            name = "Hearthstone",
            short = "HS",
            icon = hearthIcon or 134414,  -- Fallback to common hearth icon
            cooldown = cooldown,
            category = "HEARTHSTONE",
            availableHearthstones = allAvailable,  -- Store all options for random selection
        })
    end
    
    -- Add all unique cooldown hearthstones (these are separate, not randomized)
    for _, data in ipairs(TD.HEARTHSTONE_UNIQUE or {}) do
        local available = false
        local name, icon
        
        if data.type == "item" then
            available = HasItem(data.itemID)
            if available then
                name, icon = GetItemDetails(data.itemID)
            end
        end
        
        if available then
            local cooldown = GetCooldownInfo(false, data.itemID)
            table.insert(results, {
                type = "item",
                itemID = data.itemID,
                name = name or data.name,
                icon = icon,
                cooldown = cooldown,
                category = "HEARTHSTONE",
            })
        end
    end
    
    return results
end

function Scanner:ScanClassSpells()
    local results = {}
    
    for _, data in ipairs(TD.CLASS or {}) do
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
    
    for _, data in ipairs(TD.MAGE_TELEPORT or {}) do
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
    
    for _, data in ipairs(TD.MAGE_PORTAL or {}) do
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
    
    for _, data in ipairs(TD.TOY or {}) do
        if MeetsFactionRequirement(data) then
            local itemID = data.itemID
            local available = false
            local name, icon
            
            if data.type == "item" then
                available = HasItem(itemID)
            else
                available = IsToyOwned(itemID)
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
            local name, _, skillRank = GetProfessionInfo(profIndex)
            if name and name:lower():find("engineering") then
                hasEngineering = true
                rank = skillRank
                break
            end
        end
    end
    
    if not hasEngineering then
        return results
    end
    
    for _, data in ipairs(TD.ENGINEER or {}) do
        if MeetsFactionRequirement(data) and (not data.reqSkill or rank >= data.reqSkill) then
            local available = false
            local name, icon
            local itemID = data.itemID
            
            if data.type == "toy" then
                available = IsToyOwned(itemID)
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

-- ============================================================================
-- MAIN SCAN FUNCTION
-- ============================================================================

function Scanner:ScanAll()
    local allTeleports = {}
    
    -- Scan seasonal content first (highest priority)
    allTeleports.SEASONAL_DUNGEON = self:ScanSeasonalDungeons()
    allTeleports.SEASONAL_RAID = self:ScanSeasonalRaids()
    
    -- Hearthstones (deduplicated)
    allTeleports.HEARTHSTONE = self:ScanHearthstones()
    
    -- Class teleports
    allTeleports.CLASS = self:ScanClassSpells()
    
    -- Mage spells (separated)
    allTeleports.MAGE_TELEPORT = self:ScanMageTeleports()
    allTeleports.MAGE_PORTAL = self:ScanMagePortals()
    
    -- Build set of seasonal spells to exclude from expansion categories
    local seasonalSpells = {}
    for _, spellID in ipairs(TD.CURRENT_SEASON_DUNGEONS) do
        seasonalSpells[spellID] = true
    end
    for _, spellID in ipairs(TD.CURRENT_SEASON_RAIDS) do
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
    
    allTeleports.TWW_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.TWW_DUNGEON, "TWW_DUNGEON"))
    allTeleports.TWW_RAID = filterSeasonal(self:ScanDungeonCategory(TD.TWW_RAID, "TWW_RAID"))
    allTeleports.DF_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.DF_DUNGEON, "DF_DUNGEON"))
    allTeleports.DF_RAID = filterSeasonal(self:ScanDungeonCategory(TD.DF_RAID, "DF_RAID"))
    allTeleports.SL_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.SL_DUNGEON, "SL_DUNGEON"))
    allTeleports.SL_RAID = filterSeasonal(self:ScanDungeonCategory(TD.SL_RAID, "SL_RAID"))
    allTeleports.BFA_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.BFA_DUNGEON, "BFA_DUNGEON"))
    allTeleports.LEGION_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.LEGION_DUNGEON, "LEGION_DUNGEON"))
    allTeleports.WOD_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.WOD_DUNGEON, "WOD_DUNGEON"))
    allTeleports.MOP_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.MOP_DUNGEON, "MOP_DUNGEON"))
    allTeleports.CATA_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.CATA_DUNGEON, "CATA_DUNGEON"))
    allTeleports.CLASSIC_DUNGEON = filterSeasonal(self:ScanDungeonCategory(TD.CLASSIC_DUNGEON, "CLASSIC_DUNGEON"))
    
    -- Engineering and toys
    allTeleports.ENGINEER = self:ScanEngineeringSpells()
    allTeleports.TOY = self:ScanToys()
    
    return allTeleports
end

-- Returns flattened list with category order preserved (no dividers)
function Scanner:GetOrderedList()
    local allByCategory = self:ScanAll()
    local ordered = {}
    
    for _, category in ipairs(TD.CategoryOrder) do
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
function Scanner:RefreshCooldowns(teleportList)
    for _, item in ipairs(teleportList) do
        if item.type == "random_hearthstone" then
            -- For random hearthstone, get cooldown from first available hearthstone
            if item.availableHearthstones and #item.availableHearthstones > 0 then
                item.cooldown = GetCooldownInfo(false, item.availableHearthstones[1].itemID)
            end
        else
            local isSpell = item.type == "spell"
            local id = isSpell and item.spellID or item.itemID
            if id then
                item.cooldown = GetCooldownInfo(isSpell, id)
            end
        end
    end
end
