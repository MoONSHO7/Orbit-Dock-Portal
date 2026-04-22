-- PortalSchema.lua: Settings UI schema for the Portal Dock plugin (Layout + Categories tabs).

local _, addon = ...
local Orbit = Orbit
local L = Orbit.L

-- [ MODULE ] ----------------------------------------------------------------------------------------
local Schema = {}
addon.PortalSchema = Schema

function Schema.Build(plugin, dialog, systemFrame, ctx)
    local PD = addon.PortalData
    local Scanner = addon.PortalScanner
    local Combat = addon.PortalCombat
    local SB = Orbit.Engine.SchemaBuilder
    local schema = { controls = {}, extraButtons = {} }

    SB:SetTabRefreshCallback(dialog, plugin, systemFrame)
    local currentTab = SB:AddSettingsTabs(schema, dialog, { "Layout", "Categories" }, "Layout")

    if currentTab == "Layout" then
        table.insert(schema.controls, { type = "checkbox", key = "HideLongCooldowns", label = L.PLU_PORTAL_HIDE_LONG_CD, default = true })
        table.insert(schema.controls, {
            type = "slider", key = "FadeEffect", label = L.PLU_PORTAL_FADE_EFFECT,
            min = 0, max = 100, step = 5, default = 20,
            formatter = function(v) return v == 0 and L.PLU_PORTAL_FADE_OFF or L.PLU_PORTAL_FADE_PCT_F:format(v) end,
        })
        table.insert(schema.controls, { type = "slider", key = "IconSize",    label = L.PLU_PORTAL_ICON_SIZE,    min = 24, max = 40,  step = 2, default = 34 })
        table.insert(schema.controls, { type = "slider", key = "Spacing",     label = L.PLU_PORTAL_ICON_PADDING, min = 0,  max = 20,  step = 1, default = 3  })
        table.insert(schema.controls, { type = "slider", key = "MaxVisible",  label = L.PLU_PORTAL_MAX_VISIBLE,  min = 3,  max = 21,  step = 2, default = 9  })
        table.insert(schema.controls, { type = "slider", key = "Compactness", label = L.PLU_PORTAL_COMPACTNESS,  min = 0,  max = 100, step = 1, default = 0  })
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
                        local enabled = plugin:GetSetting(1, "EnabledCategories") or {}
                        enabled[cat] = val
                        plugin:SetSetting(1, "EnabledCategories", enabled)
                        if Combat.CanInteract() then ctx.RefreshDock() end
                    end,
                    getValue = function()
                        local enabled = plugin:GetSetting(1, "EnabledCategories") or {}
                        return enabled[cat] ~= false
                    end,
                })
            end
        end
    end

    Orbit.Engine.Config:Render(dialog, systemFrame, plugin, schema)
end
