-- TeleportData.lua
-- Static database of teleport spells, toys, and items organized by category

local _, addon = ...
addon.TeleportData = {}

local TD = addon.TeleportData

-- ============================================================================
-- CATEGORY CONFIGURATION
-- ============================================================================

-- Category order for dock display (priority order)
TD.CategoryOrder = {
    "HEARTHSTONE",          -- Hearthstones (FIRST - default position)
    "SEASONAL_DUNGEON",     -- Current M+ rotation dungeons
    "SEASONAL_RAID",        -- Current raid tier
    "CLASS",                -- Class-specific (e.g., DK Gate, Monk Zen, Druid Dreamwalk)
    "MAGE_TELEPORT",        -- Mage self teleports
    "MAGE_PORTAL",          -- Mage portals for groups
    "TWW_DUNGEON",          -- The War Within dungeons
    "TWW_RAID",             -- The War Within raids
    "DF_DUNGEON",           -- Dragonflight dungeons
    "DF_RAID",              -- Dragonflight raids
    "SL_DUNGEON",           -- Shadowlands dungeons
    "SL_RAID",              -- Shadowlands raids
    "BFA_DUNGEON",          -- Battle for Azeroth dungeons
    "LEGION_DUNGEON",       -- Legion dungeons
    "WOD_DUNGEON",          -- Warlords of Draenor dungeons
    "MOP_DUNGEON",          -- Mists of Pandaria dungeons
    "CATA_DUNGEON",         -- Cataclysm dungeons
    "CLASSIC_DUNGEON",      -- Classic dungeons
    "ENGINEER",             -- Engineering teleports
    "TOY",                  -- Misc teleport toys
}

TD.CategoryNames = {
    SEASONAL_DUNGEON = "Current Season",
    SEASONAL_RAID = "Current Raid",
    HEARTHSTONE = "Hearthstone",
    CLASS = "Class Teleports",
    MAGE_TELEPORT = "Mage Teleports",
    MAGE_PORTAL = "Mage Portals",
    TWW_DUNGEON = "TWW Dungeons",
    TWW_RAID = "TWW Raids",
    DF_DUNGEON = "DF Dungeons",
    DF_RAID = "DF Raids",
    SL_DUNGEON = "SL Dungeons",
    SL_RAID = "SL Raids",
    BFA_DUNGEON = "BfA Dungeons",
    LEGION_DUNGEON = "Legion Dungeons",
    WOD_DUNGEON = "WoD Dungeons",
    MOP_DUNGEON = "MoP Dungeons",
    CATA_DUNGEON = "Cata Dungeons",
    CLASSIC_DUNGEON = "Classic Dungeons",
    ENGINEER = "Engineering",
    TOY = "Teleport Toys",
}

-- ============================================================================
-- CURRENT SEASON CONFIGURATION (Update each season!)
-- ============================================================================

-- The War Within Season 3 dungeons (M+ rotation)
TD.CURRENT_SEASON_DUNGEONS = {
    1237215,  -- Eco-Dome Al'dani (new in S3)
    445417,   -- Ara-Kara, City of Echoes
    445414,   -- The Dawnbreaker
    1216786,  -- Operation: Floodgate
    445444,   -- Priory of the Sacred Flame
    354465,   -- Halls of Atonement (Shadowlands)
    367416,   -- Tazavesh, the Veiled Market (Shadowlands)
}

-- Current raid tier (Season 3)
TD.CURRENT_SEASON_RAIDS = {
    1239155,  -- Manaforge Omega
}

-- ============================================================================
-- DUNGEON PORTALS BY EXPANSION
-- ============================================================================

-- The War Within
TD.TWW_DUNGEON = {
    { spellID = 1216786, name = "Operation: Floodgate", short = "FLOOD", challengeModeID = 525 },
    { spellID = 1237215, name = "Eco-Dome Al'dani", short = "ECO", challengeModeID = 542 },
    { spellID = 445416, name = "City of Threads", short = "COT", challengeModeID = 502 },
    { spellID = 445269, name = "The Stonevault", short = "SV", challengeModeID = 501 },
    { spellID = 445414, name = "The Dawnbreaker", short = "DB", challengeModeID = 505 },
    { spellID = 445417, name = "Ara-Kara, City of Echoes", short = "AK", challengeModeID = 503 },
    { spellID = 445444, name = "Priory of the Sacred Flame", short = "PSF", challengeModeID = 499 },
    { spellID = 445418, name = "Siege of Boralus", short = "SoB", challengeModeID = 353, faction = "Alliance" },
    { spellID = 464256, name = "Siege of Boralus", short = "SoB", challengeModeID = 353, faction = "Horde" },
    { spellID = 445440, name = "Cinderbrew Meadery", short = "BREW", challengeModeID = 506 },
    { spellID = 467546, name = "Cinderbrew Meadery (Alt)", short = "BREW", challengeModeID = 506 },
    { spellID = 445441, name = "Darkflame Cleft", short = "DFC", challengeModeID = 504 },
    { spellID = 445443, name = "The Rookery", short = "ROOK", challengeModeID = 500 },
}

TD.TWW_RAID = {
    { spellID = 1239155, name = "Manaforge Omega", short = "MO" },
    { spellID = 1226482, name = "Liberation of Undermine", short = "LoU" },
}

-- Dragonflight
TD.DF_DUNGEON = {
    { spellID = 393279, name = "The Azure Vault", short = "AV" },
    { spellID = 393273, name = "Algeth'ar Academy", short = "AA" },
    { spellID = 393262, name = "The Nokhud Offensive", short = "NO" },
    { spellID = 393256, name = "Ruby Life Pools", short = "RLP" },
    { spellID = 393276, name = "Neltharus", short = "NELT" },
    { spellID = 393283, name = "Halls of Infusion", short = "HOI" },
    { spellID = 393267, name = "Brackenhide Hollow", short = "BH" },
    { spellID = 424197, name = "Dawn of the Infinite", short = "DOTI" },
}

TD.DF_RAID = {
    { spellID = 432257, name = "Aberrus", short = "ABER" },
    { spellID = 432254, name = "Vault of the Incarnates", short = "VOTI" },
    { spellID = 432258, name = "Amirdrassil", short = "AMIR" },
}

-- Shadowlands
TD.SL_DUNGEON = {
    { spellID = 354462, name = "The Necrotic Wake", short = "NW", challengeModeID = 376 },
    { spellID = 354463, name = "Plaguefall", short = "PF", challengeModeID = 379 },
    { spellID = 354464, name = "Mists of Tirna Scithe", short = "MOTS", challengeModeID = 375 },
    { spellID = 354465, name = "Halls of Atonement", short = "HoA", challengeModeID = 378 },
    { spellID = 354466, name = "Spires of Ascension", short = "SoA", challengeModeID = 380 },
    { spellID = 354467, name = "Theater of Pain", short = "TOP", challengeModeID = 382 },
    { spellID = 354468, name = "De Other Side", short = "DOS", challengeModeID = 377 },
    { spellID = 354469, name = "Sanguine Depths", short = "SD", challengeModeID = 381 },
    { spellID = 367416, name = "Tazavesh, the Veiled Market", short = "TAZ", challengeModeID = 391 },
}

TD.SL_RAID = {
    { spellID = 373190, name = "Castle Nathria", short = "CN" },
    { spellID = 373191, name = "Sanctum of Domination", short = "SOD" },
    { spellID = 373192, name = "Sepulcher of the First Ones", short = "SOTO" },
}

-- Battle for Azeroth
TD.BFA_DUNGEON = {
    { spellID = 424167, name = "Waycrest Manor", short = "WM" },
    { spellID = 373274, name = "Operation: Mechagon", short = "MECH" },
    { spellID = 410074, name = "The Underrot", short = "UR" },
    { spellID = 410071, name = "Freehold", short = "FH" },
    { spellID = 424187, name = "Atal'Dazar", short = "AD" },
    { spellID = 467553, name = "The MOTHERLODE!!", short = "ML" },
}

-- Legion
TD.LEGION_DUNGEON = {
    { spellID = 410078, name = "Neltharion's Lair", short = "NL" },
    { spellID = 393764, name = "Halls of Valor", short = "HoV" },
    { spellID = 393766, name = "Court of Stars", short = "CoS" },
    { spellID = 424163, name = "Darkheart Thicket", short = "DHT" },
    { spellID = 424153, name = "Black Rook Hold", short = "BRH" },
    { spellID = 373262, name = "Karazhan", short = "KARA" },
}

-- Warlords of Draenor
TD.WOD_DUNGEON = {
    { spellID = 159897, name = "Auchindoun" },
    { spellID = 159895, name = "Bloodmaul Slag Mines" },
    { spellID = 159901, name = "The Everbloom" },
    { spellID = 159900, name = "Grimrail Depot" },
    { spellID = 159896, name = "Iron Docks" },
    { spellID = 159899, name = "Shadowmoon Burial Grounds" },
    { spellID = 159898, name = "Skyreach" },
    { spellID = 159902, name = "Upper Blackrock Spire" },
}

-- Mists of Pandaria
TD.MOP_DUNGEON = {
    { spellID = 131225, name = "Gate of the Setting Sun" },
    { spellID = 131222, name = "Mogu'shan Palace" },
    { spellID = 131232, name = "Scholomance" },
    { spellID = 131206, name = "Shado-Pan Monastery" },
    { spellID = 131228, name = "Siege of Niuzao" },
    { spellID = 131205, name = "Stormstout Brewery" },
    { spellID = 131204, name = "Temple of the Jade Serpent" },
}

-- Cataclysm
TD.CATA_DUNGEON = {
    { spellID = 445424, name = "Grim Batol" },
    { spellID = 410080, name = "Vortex Pinnacle" },
    { spellID = 424142, name = "Throne of the Tides" },
}

-- Classic
TD.CLASSIC_DUNGEON = {
    { spellID = 131231, name = "Scarlet Halls" },
    { spellID = 131229, name = "Scarlet Monastery" },
}

-- ============================================================================
-- HEARTHSTONES
-- All hearthstones that share the main hearthstone cooldown are grouped
-- The scanner will pick ONE randomly from available ones
-- ============================================================================

-- Hearthstones that share the main cooldown (will be deduplicated)
TD.HEARTHSTONE_SHARED = {
    -- Primary Hearthstone
    { itemID = 6948, name = "Hearthstone", type = "item" },
    
    -- Toy variants (same cooldown as main Hearthstone)
    { itemID = 54452, name = "Ethereal Portal", type = "toy" },
    { itemID = 64488, name = "The Innkeeper's Daughter", type = "toy" },
    { itemID = 93672, name = "Dark Portal", type = "toy" },
    { itemID = 142542, name = "Tome of Town Portal", type = "toy" },
    { itemID = 162973, name = "Greatfather Winter's Hearthstone", type = "toy" },
    { itemID = 163045, name = "Headless Horseman's Hearthstone", type = "toy" },
    { itemID = 163206, name = "Weary Spirit Binding", type = "toy" },
    { itemID = 165669, name = "Lunar Elder's Hearthstone", type = "toy" },
    { itemID = 165670, name = "Peddlefeet's Lovely Hearthstone", type = "toy" },
    { itemID = 165802, name = "Noble Gardener's Hearthstone", type = "toy" },
    { itemID = 166746, name = "Fire Eater's Hearthstone", type = "toy" },
    { itemID = 166747, name = "Brewfest Reveler's Hearthstone", type = "toy" },
    { itemID = 168907, name = "Holographic Digitalization Hearthstone", type = "toy" },
    { itemID = 172179, name = "Eternal Traveler's Hearthstone", type = "toy" },
    { itemID = 180290, name = "Night Fae Hearthstone", type = "toy" },
    { itemID = 182773, name = "Necrolord Hearthstone", type = "toy" },
    { itemID = 183716, name = "Venthyr Sinstone", type = "toy" },
    { itemID = 184353, name = "Kyrian Hearthstone", type = "toy" },
    { itemID = 188952, name = "Dominated Hearthstone", type = "toy" },
    { itemID = 190237, name = "Broker Translocation Matrix", type = "toy" },
    { itemID = 193588, name = "Timewalker's Hearthstone", type = "toy" },
    { itemID = 200630, name = "Ohn'ir Windsage's Hearthstone", type = "toy" },
    { itemID = 206195, name = "Path of the Naaru", type = "toy" },
    { itemID = 208704, name = "Deepdweller's Earthen Hearthstone", type = "toy" },
    { itemID = 209035, name = "Hearthstone of the Flame", type = "toy" },
    { itemID = 210455, name = "Draenic Hologem", type = "toy" },
    { itemID = 212337, name = "Stone of the Hearth", type = "toy" },
    { itemID = 228940, name = "Notorious Thread's Hearthstone", type = "toy" },
}

-- Hearthstones with SEPARATE cooldowns (always show individually)
TD.HEARTHSTONE_UNIQUE = {
    { itemID = 110560, name = "Garrison Hearthstone", type = "item" },
    { itemID = 140192, name = "Dalaran Hearthstone", type = "item" },
    { itemID = 141605, name = "Flight Master's Whistle", type = "item" },
}

-- ============================================================================
-- CLASS TELEPORTS
-- ============================================================================
TD.CLASS = {
    -- Death Knight
    { spellID = 50977, name = "Death Gate", class = "DEATHKNIGHT" },
    
    -- Druid
    { spellID = 18960, name = "Teleport: Moonglade", class = "DRUID" },
    { spellID = 193753, name = "Dreamwalk", class = "DRUID" },
    
    -- Monk
    { spellID = 126892, name = "Zen Pilgrimage", class = "MONK" },
    { spellID = 126895, name = "Zen Pilgrimage: Return", class = "MONK" },
    
    -- Shaman
    { spellID = 556, name = "Astral Recall", class = "SHAMAN" },
}

-- ============================================================================
-- MAGE TELEPORTS (Personal)
-- ============================================================================
TD.MAGE_TELEPORT = {
    -- Alliance
    { spellID = 3561, name = "Teleport: Stormwind", faction = "Alliance" },
    { spellID = 3562, name = "Teleport: Ironforge", faction = "Alliance" },
    { spellID = 3565, name = "Teleport: Darnassus", faction = "Alliance" },
    { spellID = 32271, name = "Teleport: Exodar", faction = "Alliance" },
    { spellID = 49359, name = "Teleport: Theramore", faction = "Alliance" },
    { spellID = 33690, name = "Teleport: Shattrath", faction = "Alliance" },
    { spellID = 88342, name = "Teleport: Tol Barad", faction = "Alliance" },
    { spellID = 132621, name = "Teleport: Vale of Eternal Blossoms", faction = "Alliance" },
    { spellID = 176248, name = "Teleport: Stormshield", faction = "Alliance" },
    { spellID = 281403, name = "Teleport: Boralus", faction = "Alliance" },
    
    -- Horde
    { spellID = 3567, name = "Teleport: Orgrimmar", faction = "Horde" },
    { spellID = 3563, name = "Teleport: Undercity", faction = "Horde" },
    { spellID = 3566, name = "Teleport: Thunder Bluff", faction = "Horde" },
    { spellID = 32272, name = "Teleport: Silvermoon", faction = "Horde" },
    { spellID = 49358, name = "Teleport: Stonard", faction = "Horde" },
    { spellID = 35715, name = "Teleport: Shattrath", faction = "Horde" },
    { spellID = 88344, name = "Teleport: Tol Barad", faction = "Horde" },
    { spellID = 132627, name = "Teleport: Vale of Eternal Blossoms", faction = "Horde" },
    { spellID = 176242, name = "Teleport: Warspear", faction = "Horde" },
    { spellID = 281404, name = "Teleport: Dazar'alor", faction = "Horde" },
    
    -- Neutral
    { spellID = 53140, name = "Teleport: Dalaran - Northrend" },
    { spellID = 224869, name = "Teleport: Dalaran - Broken Isles" },
    { spellID = 344587, name = "Teleport: Oribos" },
    { spellID = 395277, name = "Teleport: Valdrakken" },
    { spellID = 446540, name = "Teleport: Dornogal" },
    { spellID = 120145, name = "Ancient Teleport: Dalaran" },
}

-- ============================================================================
-- MAGE PORTALS (Group)
-- ============================================================================
TD.MAGE_PORTAL = {
    -- Alliance
    { spellID = 10059, name = "Portal: Stormwind", faction = "Alliance" },
    { spellID = 11416, name = "Portal: Ironforge", faction = "Alliance" },
    { spellID = 11419, name = "Portal: Darnassus", faction = "Alliance" },
    { spellID = 32266, name = "Portal: Exodar", faction = "Alliance" },
    { spellID = 49360, name = "Portal: Theramore", faction = "Alliance" },
    { spellID = 33691, name = "Portal: Shattrath", faction = "Alliance" },
    { spellID = 88345, name = "Portal: Tol Barad", faction = "Alliance" },
    { spellID = 132620, name = "Portal: Vale of Eternal Blossoms", faction = "Alliance" },
    { spellID = 176246, name = "Portal: Stormshield", faction = "Alliance" },
    { spellID = 281400, name = "Portal: Boralus", faction = "Alliance" },
    
    -- Horde
    { spellID = 11417, name = "Portal: Orgrimmar", faction = "Horde" },
    { spellID = 11418, name = "Portal: Undercity", faction = "Horde" },
    { spellID = 11420, name = "Portal: Thunder Bluff", faction = "Horde" },
    { spellID = 32267, name = "Portal: Silvermoon", faction = "Horde" },
    { spellID = 49361, name = "Portal: Stonard", faction = "Horde" },
    { spellID = 35717, name = "Portal: Shattrath", faction = "Horde" },
    { spellID = 88346, name = "Portal: Tol Barad", faction = "Horde" },
    { spellID = 132626, name = "Portal: Vale of Eternal Blossoms", faction = "Horde" },
    { spellID = 176244, name = "Portal: Warspear", faction = "Horde" },
    { spellID = 281402, name = "Portal: Dazar'alor", faction = "Horde" },
    
    -- Neutral
    { spellID = 53142, name = "Portal: Dalaran - Northrend" },
    { spellID = 224871, name = "Portal: Dalaran - Broken Isles" },
    { spellID = 344597, name = "Portal: Oribos" },
    { spellID = 395289, name = "Portal: Valdrakken" },
    { spellID = 446534, name = "Portal: Dornogal" },
    { spellID = 120146, name = "Ancient Portal: Dalaran" },
}

-- ============================================================================
-- ENGINEERING TELEPORTS
-- ============================================================================
TD.ENGINEER = {
    -- Classic/TBC (Items)
    { itemID = 18986, name = "Ultrasafe Transporter: Gadgetzan", type = "item", reqSkill = 260 },
    { itemID = 18984, name = "Dimensional Ripper - Everlook", type = "item", reqSkill = 260 },
    { itemID = 30544, name = "Ultrasafe Transporter: Toshley's Station", type = "item", reqSkill = 350 },
    { itemID = 30542, name = "Dimensional Ripper - Area 52", type = "item", reqSkill = 350 },
    
    -- Wrath (Toy)
    { itemID = 48933, name = "Wormhole Generator: Northrend", type = "toy", reqSkill = 415 },
    
    -- Pandaria (Toy)
    { itemID = 87215, name = "Wormhole Generator: Pandaria", type = "toy", reqSkill = 600 },
    
    -- Draenor (Toy)
    { itemID = 112059, name = "Wormhole Centrifuge", type = "toy", reqSkill = 700 },
    
    -- Legion (Toy)
    { itemID = 151652, name = "Wormhole Generator: Argus", type = "toy", reqSkill = 800 },
    
    -- BfA (Toys)
    { itemID = 168807, name = "Wormhole Generator: Kul Tiras", type = "toy", reqSkill = 1, faction = "Alliance" },
    { itemID = 168808, name = "Wormhole Generator: Zandalar", type = "toy", reqSkill = 1, faction = "Horde" },
    
    -- Shadowlands (Toy)
    { itemID = 172924, name = "Wormhole Generator: Shadowlands", type = "toy", reqSkill = 1 },
    
    -- Dragonflight (Toy)
    { itemID = 198156, name = "Wyrmhole Generator: Dragon Isles", type = "toy", reqSkill = 1 },
    
    -- The War Within (Toy)
    { itemID = 221966, name = "Wormhole Generator: Khaz Algar", type = "toy", reqSkill = 1 },
}

-- ============================================================================
-- TELEPORT TOYS (Miscellaneous)
-- ============================================================================
TD.TOY = {
    { itemID = 64457, name = "The Last Relic of Argus", destination = "Random" },
    { itemID = 95567, name = "Kirin Tor Beacon", destination = "Isle of Thunder", faction = "Alliance" },
    { itemID = 95568, name = "Sunreaver Beacon", destination = "Isle of Thunder", faction = "Horde" },
    { itemID = 103678, name = "Time-Lost Artifact", destination = "Timeless Isle" },
    { itemID = 128353, name = "Admiral's Compass", destination = "Garrison Shipyard" },
    { itemID = 129276, name = "Beginner's Guide to Dimensional Rifting", destination = "Random Draenor" },
    { itemID = 118662, name = "Bladespire Relic", destination = "Frostfire Ridge", faction = "Horde" },
    { itemID = 118663, name = "Relic of Karabor", destination = "Shadowmoon Valley", faction = "Alliance" },
    { itemID = 119183, name = "Scroll of Risky Recall", destination = "Random Old Location" },
    { itemID = 136849, name = "Nature's Beacon", destination = "Dreamgrove" },
    { itemID = 139590, name = "Scroll of Teleport: Ravenholdt", destination = "Ravenholdt" },
    { itemID = 140493, name = "Adept's Guide to Dimensional Rifting", destination = "Random Legion" },
    { itemID = 151016, name = "Fractured Necrolyte Skull", destination = "Black Temple" },
    { itemID = 152964, name = "Greater Spatial Rift", destination = "Argus" },
    { itemID = 168862, name = "G.E.A.R. Tracking Beacon", destination = "Mechagon" },
    { itemID = 180817, name = "Cypher of Relocation", destination = "Oribos" },
    
    -- Rings (teleport jewelry)
    { itemID = 40586, name = "Band of the Kirin Tor", destination = "Dalaran (Northrend)", type = "item" },
    { itemID = 44934, name = "Loop of the Kirin Tor", destination = "Dalaran (Northrend)", type = "item" },
    { itemID = 44935, name = "Ring of the Kirin Tor", destination = "Dalaran (Northrend)", type = "item" },
    { itemID = 45688, name = "Inscribed Band of the Kirin Tor", destination = "Dalaran (Northrend)", type = "item" },
    { itemID = 45689, name = "Inscribed Loop of the Kirin Tor", destination = "Dalaran (Northrend)", type = "item" },
    { itemID = 45690, name = "Inscribed Ring of the Kirin Tor", destination = "Dalaran (Northrend)", type = "item" },
    { itemID = 45691, name = "Inscribed Signet of the Kirin Tor", destination = "Dalaran (Northrend)", type = "item" },
    
    -- Tabards
    { itemID = 46874, name = "Argent Crusader's Tabard", destination = "Argent Tournament", type = "item" },
    { itemID = 63378, name = "Hellscream's Reach Tabard", destination = "Tol Barad", type = "item", faction = "Horde" },
    { itemID = 63379, name = "Baradin's Wardens Tabard", destination = "Tol Barad", type = "item", faction = "Alliance" },
    
    -- Guild Cloaks
    { itemID = 65360, name = "Cloak of Coordination", destination = "Stormwind", type = "item", faction = "Alliance" },
    { itemID = 65274, name = "Cloak of Coordination", destination = "Orgrimmar", type = "item", faction = "Horde" },
    
    -- Other
    { itemID = 37863, name = "Direbrew's Remote", destination = "Blackrock Depths", type = "item" },
    { itemID = 52251, name = "Jaina's Locket", destination = "Dalaran (Northrend)", type = "item" },
}

-- ============================================================================
-- HELPER: Check if a spell is in current season
-- ============================================================================
function TD:IsCurrentSeasonDungeon(spellID)
    for _, id in ipairs(self.CURRENT_SEASON_DUNGEONS) do
        if id == spellID then return true end
    end
    return false
end

function TD:IsCurrentSeasonRaid(spellID)
    for _, id in ipairs(self.CURRENT_SEASON_RAIDS) do
        if id == spellID then return true end
    end
    return false
end
