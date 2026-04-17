-- PortalScanner.lua: Runtime scanner that detects available portals for the current character.

local _, addon = ...
addon.PortalScanner = {}

local L = Orbit.L
local Scanner = addon.PortalScanner
local PD = addon.PortalData

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local HEARTHSTONE_ITEM_ID       = 6948
local HEARTHSTONE_ICON_FALLBACK = 134414
local ENGINEERING_SKILL_LINE    = 202
local MIN_LEVEL_FOR_HOUSING     = 80

local PLAYER_CLASS = select(2, UnitClass("player"))
local PLAYER_FACTION = UnitFactionGroup("player")

local cachedHouseList

-- [ DETECTION FUNCTIONS ] ---------------------------------------------------------------------------
local function IsSpellAvailable(spellID)
    return C_SpellBook.IsSpellKnown(spellID)
end

local function IsToyOwned(itemID)
    return PlayerHasToy(itemID)
end

-- Owned AND valid in the current zone/level.
local function IsToyUsable(itemID)
    if not PlayerHasToy(itemID) then return false end
    return C_ToyBox.IsToyUsable(itemID)
end

local function HasItem(itemID)
    return C_Item.GetItemCount(itemID) > 0
end

local function MeetsFactionRequirement(data)
    if not data.faction then return true end
    return data.faction == PLAYER_FACTION
end

local function MeetsClassRequirement(data)
    if not data.class then return true end
    return data.class == PLAYER_CLASS
end

local function GetCooldownInfo(isSpell, id)
    if not id then return 0, 0 end

    local startTime, duration
    if isSpell then
        local info = C_Spell.GetSpellCooldown(id)
        if info then startTime, duration = info.startTime, info.duration end
    else
        startTime, duration = C_Container.GetItemCooldown(id)
    end

    if not startTime or not duration then return 0, 0 end
    if issecretvalue(startTime) or issecretvalue(duration) then return 0, 0 end
    if startTime <= 0 then return 0, 0 end
    local remaining = (startTime + duration) - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining, duration
end

local function GetSpellDetails(spellID)
    local info = C_Spell.GetSpellInfo(spellID)
    if info then
        return info.name, info.iconID
    end
    return nil, nil
end

-- GetItemInfo returns nil until the item cache populates; the placeholder resolves on the next refresh.
local function GetItemDetails(itemID)
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
    local name = C_Item.GetItemInfo(itemID) or L.PLU_PORTAL_ITEM_FALLBACK_F:format(itemID)
    return name, icon
end

-- [ CATEGORY SCANNERS ] -----------------------------------------------------------------------------
function Scanner:ScanDungeonCategory(categoryData, categoryName)
    local results = {}

    for _, data in ipairs(categoryData or {}) do
        if MeetsFactionRequirement(data) then
            if IsSpellAvailable(data.spellID) then
                local spellName, icon = GetSpellDetails(data.spellID)
                if spellName then
                    local cooldown, cooldownDuration = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = spellName,
                        instanceName = data.name,
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

function Scanner:ScanSeasonalDungeons()
    local results = {}
    local seasonalSpells = {}

    for _, spellID in ipairs(PD.CURRENT_SEASON_DUNGEONS) do
        seasonalSpells[spellID] = true
    end

    local dungeonCategories = {
        PD.MIDNIGHT_DUNGEON,
        PD.TWW_DUNGEON,
        PD.DF_DUNGEON,
        PD.SL_DUNGEON,
        PD.BFA_DUNGEON,
        PD.LEGION_DUNGEON,
        PD.WOD_DUNGEON,
        PD.WOTLK_DUNGEON,
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
                            name = spellName,
                            instanceName = data.name,
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

function Scanner:ScanSeasonalRaids()
    local results = {}
    local seasonalSpells = {}

    for _, spellID in ipairs(PD.CURRENT_SEASON_RAIDS) do
        seasonalSpells[spellID] = true
    end

    local raidCategories = { PD.MIDNIGHT_RAID, PD.TWW_RAID, PD.DF_RAID, PD.SL_RAID }

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
                            name = spellName,
                            instanceName = data.name,
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

-- Returns ONE unified hearthstone entry that casts a random available hearthstone on click.
function Scanner:ScanHearthstones()
    local results = {}
    local allAvailable = {}

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

    if #allAvailable > 0 then
        local cooldown, cooldownDuration = GetCooldownInfo(false, allAvailable[1].itemID)
        local _, _, _, _, hearthIcon = C_Item.GetItemInfoInstant(HEARTHSTONE_ITEM_ID)
        table.insert(results, {
            type = "random_hearthstone",
            name = L.PLU_PORTAL_HEARTHSTONE,
            short = L.PLU_PORTAL_HEARTHSTONE_SHORT,
            icon = hearthIcon or HEARTHSTONE_ICON_FALLBACK,
            cooldown = cooldown,
            cooldownDuration = cooldownDuration,
            category = "HEARTHSTONE",
            availableHearthstones = allAvailable,
        })
    end

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
                type = data.type,
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
                    local cooldown, cooldownDuration = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        cooldownDuration = cooldownDuration,
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

    if PLAYER_CLASS ~= "MAGE" then return results end

    for _, data in ipairs(PD.MAGE_TELEPORT or {}) do
        if MeetsFactionRequirement(data) then
            if IsSpellAvailable(data.spellID) then
                local name, icon = GetSpellDetails(data.spellID)
                if name then
                    local cooldown, cooldownDuration = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        cooldownDuration = cooldownDuration,
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

    if PLAYER_CLASS ~= "MAGE" then return results end

    for _, data in ipairs(PD.MAGE_PORTAL or {}) do
        if MeetsFactionRequirement(data) then
            if IsSpellAvailable(data.spellID) then
                local name, icon = GetSpellDetails(data.spellID)
                if name then
                    local cooldown, cooldownDuration = GetCooldownInfo(true, data.spellID)
                    table.insert(results, {
                        type = "spell",
                        spellID = data.spellID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        cooldownDuration = cooldownDuration,
                        category = "MAGE_TELEPORT",
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
                available = IsToyUsable(itemID)
            end

            if available then
                name, icon = GetItemDetails(itemID)
                if name then
                    local cooldown, cooldownDuration = GetCooldownInfo(false, itemID)
                    table.insert(results, {
                        type = data.type or "toy",
                        itemID = itemID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        cooldownDuration = cooldownDuration,
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

    local hasEngineering = false
    local rank = 0
    local professions = { GetProfessions() }
    for _, profIndex in pairs(professions) do
        if profIndex then
            local _, _, skillRank, _, _, _, skillLineID = GetProfessionInfo(profIndex)
            if skillLineID == ENGINEERING_SKILL_LINE then
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
                available = IsToyUsable(itemID)
            elseif data.type == "item" then
                available = HasItem(itemID)
            end

            if available then
                name, icon = GetItemDetails(itemID)
                if name then
                    local cooldown, cooldownDuration = GetCooldownInfo(false, itemID)
                    table.insert(results, {
                        type = data.type or "toy",
                        itemID = itemID,
                        name = name or data.name,
                        icon = icon,
                        cooldown = cooldown,
                        cooldownDuration = cooldownDuration,
                        category = "ENGINEER",
                    })
                end
            end
        end
    end

    return results
end

-- C_Housing may not exist on older 12.0.x builds; feature-detect before touching it.
function Scanner:ScanHousing()
    local results = {}

    if not C_Housing or not C_Housing.TeleportHome then
        return results
    end

    local hasHouse = false
    local houseInfo = nil
    local displayName = L.PLU_PORTAL_HOUSING_TELEPORT
    local neighborhoodName = nil

    if cachedHouseList and #cachedHouseList > 0 then
        hasHouse = true
        houseInfo = cachedHouseList[1]
        displayName = houseInfo.houseName or houseInfo.neighborhoodName or L.PLU_PORTAL_HOUSING_MY_PLOT
        neighborhoodName = houseInfo.neighborhoodName
    end

    if not hasHouse and C_Housing.GetTrackedHouseGuid then
        local trackedGuid = C_Housing.GetTrackedHouseGuid()
        if trackedGuid then
            hasHouse = true
            displayName = L.PLU_PORTAL_HOUSING_MY_PLOT
        end
    end

    -- Level 80+ with housing API can likely use housing; the secure macro handles the no-house case.
    if not hasHouse then
        local level = UnitLevel("player")
        if level and level >= MIN_LEVEL_FOR_HOUSING then
            hasHouse = true
            displayName = L.PLU_PORTAL_HOUSING_TELEPORT
        end
    end

    if not hasHouse then
        return results
    end

    local cooldown, cooldownDuration = 0, 0
    local cdInfo = C_Housing.GetVisitCooldownInfo and C_Housing.GetVisitCooldownInfo()
    if cdInfo and cdInfo.startTime and cdInfo.duration then
        cooldown = math.max(0, (cdInfo.startTime + cdInfo.duration) - GetTime())
        cooldownDuration = cdInfo.duration
    end

    table.insert(results, {
        type = "housing",
        name = displayName,
        instanceName = neighborhoodName,
        short = L.PLU_PORTAL_HOUSING_SHORT,
        iconAtlas = "dashboard-panel-homestone-teleport-button",
        cooldown = cooldown,
        cooldownDuration = cooldownDuration,
        category = "HOUSING",
        houseInfo = houseInfo,
    })

    return results
end

function Scanner:UpdateHousingCache(houseInfos)
    cachedHouseList = houseInfos
end

function Scanner:RequestHousingData()
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        C_Housing.GetPlayerOwnedHouses()
    end
end

-- [ MAIN SCAN FUNCTION ] ----------------------------------------------------------------------------
function Scanner:ScanAll()
    local allPortals = {}

    allPortals.SEASONAL_DUNGEON = self:ScanSeasonalDungeons()
    allPortals.SEASONAL_RAID = self:ScanSeasonalRaids()
    allPortals.HEARTHSTONE = self:ScanHearthstones()
    allPortals.HOUSING = self:ScanHousing()
    allPortals.CLASS = self:ScanClassSpells()

    -- Mage spells: self teleports + group portals share one category.
    allPortals.MAGE_TELEPORT = self:ScanMageTeleports()
    for _, item in ipairs(self:ScanMagePortals()) do
        table.insert(allPortals.MAGE_TELEPORT, item)
    end

    local seasonalSpells = {}
    for _, spellID in ipairs(PD.CURRENT_SEASON_DUNGEONS) do
        seasonalSpells[spellID] = true
    end
    for _, spellID in ipairs(PD.CURRENT_SEASON_RAIDS) do
        seasonalSpells[spellID] = true
    end

    local function filterSeasonal(results)
        local filtered = {}
        for _, item in ipairs(results) do
            if not seasonalSpells[item.spellID] then
                table.insert(filtered, item)
            end
        end
        return filtered
    end

    allPortals.MIDNIGHT_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.MIDNIGHT_DUNGEON, "MIDNIGHT_DUNGEON"))
    allPortals.TWW_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.TWW_DUNGEON, "TWW_DUNGEON"))
    allPortals.DF_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.DF_DUNGEON, "DF_DUNGEON"))
    allPortals.SL_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.SL_DUNGEON, "SL_DUNGEON"))
    allPortals.BFA_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.BFA_DUNGEON, "BFA_DUNGEON"))

    -- Raids: every expansion's raid portals fold into a single RAID category.
    allPortals.RAID = {}
    local function appendRaids(rawRaids)
        for _, item in ipairs(filterSeasonal(rawRaids)) do
            item.category = "RAID"
            table.insert(allPortals.RAID, item)
        end
    end
    appendRaids(self:ScanDungeonCategory(PD.MIDNIGHT_RAID, "RAID"))
    appendRaids(self:ScanDungeonCategory(PD.TWW_RAID,      "RAID"))
    appendRaids(self:ScanDungeonCategory(PD.DF_RAID,       "RAID"))
    appendRaids(self:ScanDungeonCategory(PD.SL_RAID,       "RAID"))
    allPortals.LEGION_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.LEGION_DUNGEON, "LEGION_DUNGEON"))
    allPortals.WOD_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.WOD_DUNGEON, "WOD_DUNGEON"))
    allPortals.WOTLK_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.WOTLK_DUNGEON, "WOTLK_DUNGEON"))
    allPortals.MOP_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.MOP_DUNGEON, "MOP_DUNGEON"))
    allPortals.CATA_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.CATA_DUNGEON, "CATA_DUNGEON"))
    allPortals.CLASSIC_DUNGEON = filterSeasonal(self:ScanDungeonCategory(PD.CLASSIC_DUNGEON, "CLASSIC_DUNGEON"))

    allPortals.ENGINEER = self:ScanEngineeringSpells()
    allPortals.TOY = self:ScanToys()

    return allPortals
end

-- Flattened list with CategoryOrder priority preserved (no dividers).
function Scanner:GetOrderedList()
    local allByCategory = self:ScanAll()
    local ordered = {}

    for _, category in ipairs(PD.CategoryOrder) do
        local items = allByCategory[category]
        if items and #items > 0 then
            for _, item in ipairs(items) do
                item.category = category
                table.insert(ordered, item)
            end
        end
    end

    return ordered
end

-- Refresh cooldowns for an existing list (cheaper than a full rescan).
function Scanner:RefreshCooldowns(portalList)
    for _, item in ipairs(portalList) do
        if item.type == "random_hearthstone" then
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
