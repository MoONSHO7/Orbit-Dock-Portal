local _, addon = ...
local Services = addon.LibOrbitUI.CreateContext({
    owner = addon,
    name = "OrbitPortal",
    onDisplayChanged = function()
        if addon.PortalBoot then
            addon.PortalBoot.Apply()
        end
    end,
})
addon.PortalServices = Services

local lastOrientation = "LEFT"
local SHADOW_OFFSET = 1

function Services.DetectOrientation(frame)
    lastOrientation = addon.LibOrbitUI.Geometry:DetectOrientation(frame, lastOrientation)
    return lastOrientation
end

Services.SetFont =
    addon.LibOrbitUI.Text.CreateFontSetter(Services.pixel, "OrbitPortalFont", SHADOW_OFFSET, -SHADOW_OFFSET)

function Services.GetFontPath()
    return STANDARD_TEXT_FONT
end

function Services.ApplyFontOverrides(region, overrides, size, path)
    Services.SetFont(region, path, size, "OUTLINE")
end

Services.ApplyTimerOverrides = Services.ApplyFontOverrides

Services.ApplyTextPosition = addon.LibOrbitUI.TextPosition.CreateSetter(Services.pixel)

function Services.Message(message)
    print("|cff80bfffOrbit Portal:|r " .. message)
end
