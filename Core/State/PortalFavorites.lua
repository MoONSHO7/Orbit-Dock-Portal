-- PortalFavorites.lua: Favorite-portal persistence model. Keyed on spellID / itemID / name.

local _, addon = ...

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Favorites = {}
addon.PortalFavorites = Favorites

function Favorites.GetKey(data)
    if not data then return nil end
    return data.spellID or data.itemID or data.name
end

function Favorites.IsFavorite(plugin, data)
    local key = Favorites.GetKey(data)
    if not key then return false end
    local favs = plugin:GetSetting(1, "Favorites") or {}
    return favs[tostring(key)] == true
end

function Favorites.Toggle(plugin, data)
    local key = Favorites.GetKey(data)
    if not key then return end
    local favs = plugin:GetSetting(1, "Favorites") or {}
    local k = tostring(key)
    favs[k] = (not favs[k]) or nil
    plugin:SetSetting(1, "Favorites", favs)
end
