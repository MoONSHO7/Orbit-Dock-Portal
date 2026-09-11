local _, addon = ...
local L = addon.L
local Schema = {}
addon.PortalSchema = Schema

local function Slider(key, label, minimum, maximum, step, formatter)
    return {
        type = "slider",
        key = key,
        label = label,
        min = minimum,
        max = maximum,
        step = step,
        default = addon.PortalDefaults[key],
        formatter = formatter,
    }
end

local function ComponentControl(plugin, ctx, key, label)
    return {
        type = "checkbox",
        label = label,
        default = key ~= "DungeonShort",
        getValue = function()
            for _, disabled in ipairs(plugin:GetSetting(1, "DisabledComponents")) do
                if disabled == key then
                    return false
                end
            end
            return true
        end,
        onChange = function(shown)
            local values = {}
            for _, disabled in ipairs(plugin:GetSetting(1, "DisabledComponents")) do
                if disabled ~= key then
                    values[#values + 1] = disabled
                end
            end
            if not shown then
                values[#values + 1] = key
            end
            plugin:SetSetting(1, "DisabledComponents", values)
            ctx.RequestRefresh()
        end,
    }
end

function Schema.Tabs(plugin, ctx)
    return {
        {
            id = "layout",
            label = L.PLU_PORTAL_TAB_LAYOUT,
            controls = {
                {
                    type = "checkbox",
                    key = "HideLongCooldowns",
                    label = L.PLU_PORTAL_HIDE_LONG_CD,
                    default = addon.PortalDefaults.HideLongCooldowns,
                },
                Slider("FadeEffect", L.PLU_PORTAL_FADE_EFFECT, 0, 100, 5, function(v)
                    return v == 0 and L.PLU_PORTAL_FADE_OFF or L.PLU_PORTAL_FADE_PCT_F:format(v)
                end),
                Slider("IconSize", L.PLU_PORTAL_ICON_SIZE, 24, 40, 2),
                Slider("Spacing", L.PLU_PORTAL_ICON_PADDING, 0, 50, 1, function(v)
                    return tostring(v) .. " px"
                end),
                Slider("MaxVisible", L.PLU_PORTAL_MAX_VISIBLE, 3, 21, 2),
                Slider("Compactness", L.PLU_PORTAL_CURVE, 0, 100, 1),
                Slider("Animation", L.PLU_PORTAL_ANIMATION, 0, 2, 1, function(v)
                    return v == 2 and L.PLU_PORTAL_ANIM_FADE
                        or v == 1 and L.PLU_PORTAL_ANIM_SLIDE
                        or L.PLU_PORTAL_FADE_OFF
                end),
            },
        },
        {
            id = "behaviours",
            label = L.PLU_PORTAL_TAB_BEHAVIOURS,
            controls = {
                {
                    type = "checkbox",
                    key = "EnableKeyboardSearch",
                    label = L.PLU_PORTAL_ENABLE_KEYBOARD_SEARCH,
                    default = addon.PortalDefaults.EnableKeyboardSearch,
                },
                ComponentControl(plugin, ctx, "DungeonScore", L.PLU_PORTAL_RATING),
                ComponentControl(plugin, ctx, "DungeonShort", L.PLU_PORTAL_SHORT_LABEL),
                ComponentControl(plugin, ctx, "FavouriteStar", L.PLU_PORTAL_FAVORITE_MARKER),
                ComponentControl(plugin, ctx, "Timer", L.PLU_PORTAL_TIMER),
            },
        },
        {
            id = "categories",
            label = L.PLU_PORTAL_TAB_CATEGORIES,
            controls = function()
                local controls, counts = {}, {}
                for _, item in ipairs(addon.PortalScanner:GetOrderedList()) do
                    counts[item.category] = (counts[item.category] or 0) + 1
                end
                for _, category in ipairs(addon.PortalData.CategoryOrder) do
                    local key, count = category, counts[category] or 0
                    if key ~= "FAVORITE" and count > 0 then
                        controls[#controls + 1] = {
                            type = "checkbox",
                            label = addon.PortalData.CategoryNames[key],
                            default = true,
                            valueText = tostring(count),
                            getValue = function()
                                return plugin:GetSetting(1, "EnabledCategories")[key] ~= false
                            end,
                            onChange = function(value)
                                local enabled = CopyTable(plugin:GetSetting(1, "EnabledCategories"))
                                enabled[key] = value
                                plugin:SetSetting(1, "EnabledCategories", enabled)
                                ctx.RequestRefresh()
                            end,
                        }
                    end
                end
                return controls
            end,
        },
    }
end
