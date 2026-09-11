local _, addon = ...
local STORE_VERSION = 1
local PROFILE_ID = "default"
local Store = {}
addon.PortalStore = Store
local NUMBER_RULES = {
    IconSize = { 24, 40, 2 },
    Spacing = { 0, 50, 1 },
    MaxVisible = { 3, 21, 2 },
    FadeEffect = { 0, 100, 5 },
    Compactness = { 0, 100, 1 },
    Animation = { 0, 2, 1 },
}
local POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}
local AXIS_X = { LEFT = true, CENTER = true, RIGHT = true }
local AXIS_Y = { TOP = true, CENTER = true, BOTTOM = true }

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function IsBooleanMap(value)
    for key, flag in pairs(value) do
        if type(key) ~= "string" or type(flag) ~= "boolean" then
            return false
        end
    end
    return true
end

local function IsValid(key, value)
    local default = addon.PortalDefaults[key]
    if type(value) ~= type(default) then
        return false
    end
    local rule = NUMBER_RULES[key]
    if rule then
        return IsFinite(value) and value >= rule[1] and value <= rule[2] and (value - rule[1]) % rule[3] == 0
    elseif key == "Position" then
        return POINTS[value.point] == true
            and (value.relativePoint == nil or POINTS[value.relativePoint] == true)
            and IsFinite(value.x)
            and IsFinite(value.y)
    elseif key == "Favorites" or key == "EnabledCategories" then
        return IsBooleanMap(value)
    elseif key == "DisabledComponents" then
        for index, component in pairs(value) do
            if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(component) ~= "string" then
                return false
            end
        end
    elseif key == "ComponentPositions" then
        for component, position in pairs(value) do
            if
                type(component) ~= "string"
                or type(position) ~= "table"
                or not AXIS_X[position.anchorX]
                or not AXIS_Y[position.anchorY]
                or not IsFinite(position.offsetX)
                or not IsFinite(position.offsetY)
                or (position.justifyH ~= nil and not AXIS_X[position.justifyH])
            then
                return false
            end
        end
    elseif key == "Anchor" then
        return value == false
    end
    return default ~= nil
end

function Store:Initialize()
    if OrbitPortalDB ~= nil and (type(OrbitPortalDB) ~= "table" or OrbitPortalDB.version ~= STORE_VERSION) then
        return false
    end
    if OrbitPortalDB == nil then
        OrbitPortalDB = { version = STORE_VERSION, profiles = { [PROFILE_ID] = { settings = {} } } }
    end
    local profiles = OrbitPortalDB.profiles
    local profile = type(profiles) == "table" and profiles[PROFILE_ID]
    if type(profile) ~= "table" or type(profile.settings) ~= "table" then
        return false
    end
    self.profile = profile
    return true
end

function Store:Get(key)
    assert(addon.PortalDefaults[key] ~= nil, "unknown Portal setting: " .. tostring(key))
    local value = self.profile.settings[key]
    if value == nil or not IsValid(key, value) then
        value = addon.PortalDefaults[key]
    end
    return type(value) == "table" and CopyTable(value) or value
end

function Store:Set(key, value)
    assert(addon.PortalDefaults[key] ~= nil, "unknown Portal setting: " .. tostring(key))
    assert(value == nil or IsValid(key, value), "invalid Portal setting: " .. tostring(key))
    self.profile.settings[key] = type(value) == "table" and CopyTable(value) or value
end

function Store:Reset()
    wipe(self.profile.settings)
end
