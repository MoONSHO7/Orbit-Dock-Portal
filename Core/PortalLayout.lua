-- PortalLayout.lua: Pure, stateless layout math — arc-wrap positioning and edge-fade alpha.

local _, addon = ...

-- [ CONSTANTS ] -------------------------------------------------------------------------------------
local MIN_FADE_ALPHA = 0.05
local FADE_CURVE_UNIT = 20  -- Slider amount that yields a classic cosine curve (power 1).

-- Cache globals (hot path).
local math_abs   = math.abs
local math_min   = math.min
local math_max   = math.max
local math_sin   = math.sin
local math_cos   = math.cos
local math_pi    = math.pi

local Layout = {}
addon.PortalLayout = Layout

-- [ HELPERS ] ---------------------------------------------------------------------------------------
-- Normalize maxVisible to an odd integer clamped to [3, totalItems].
function Layout.NormalizeMaxVisible(maxVisible, totalItems)
    if maxVisible % 2 == 0 then maxVisible = maxVisible - 1 end
    return math_max(3, math_min(maxVisible, totalItems or maxVisible))
end

-- Min/max of sin(theta) over [-halfMax, halfMax]: when halfMax > pi/2 the peak at ±pi/2 hits ±1.
local function SinRange(halfMax)
    if halfMax > math_pi / 2 then return -1, 1 end
    local s = math_sin(halfMax)
    return -s, s
end

-- compactness 0..1 wraps the chain onto a circle (0 = straight, 1 ≈ full circle with one slot gap).
function Layout.CalculatePosition(displayIndex, maxVisible, iconSize, spacing, compactness)
    local segment = iconSize + spacing
    local linearAxial = displayIndex * segment + iconSize / 2
    if compactness <= 0.001 or maxVisible < 2 then
        return linearAxial, 0
    end
    local totalLength = (maxVisible - 1) * segment
    local thetaMax = compactness * 2 * math_pi * (maxVisible - 1) / maxVisible
    local radius = totalLength / thetaMax
    local t = displayIndex / (maxVisible - 1)
    local theta = (2 * t - 1) * thetaMax / 2
    local x = radius * math_sin(theta)
    local y = radius * (math_cos(theta) - math_cos(thetaMax / 2))
    local minSin = SinRange(thetaMax / 2)
    local xMin = radius * minSin
    return (x - xMin) + iconSize / 2, y
end

-- Max perpendicular bulge at the middle of the wrap (used for dock thickness).
function Layout.CalculatePerpExtent(maxVisible, iconSize, spacing, compactness)
    if compactness <= 0.001 or maxVisible < 2 then return 0 end
    local totalLength = (maxVisible - 1) * (iconSize + spacing)
    local thetaMax = compactness * 2 * math_pi * (maxVisible - 1) / maxVisible
    local radius = totalLength / thetaMax
    return radius * (1 - math_cos(thetaMax / 2))
end

-- Full axial span (used for dock length).
function Layout.CalculateAxialExtent(maxVisible, iconSize, spacing, compactness)
    local segment = iconSize + spacing
    if compactness <= 0.001 or maxVisible < 2 then
        return (maxVisible - 1) * segment + iconSize
    end
    local totalLength = (maxVisible - 1) * segment
    local thetaMax = compactness * 2 * math_pi * (maxVisible - 1) / maxVisible
    local radius = totalLength / thetaMax
    local minSin, maxSin = SinRange(thetaMax / 2)
    return radius * (maxSin - minSin) + iconSize
end

-- fadeAmount: 0 = no fade, 20 = classic cosine, 100 = very sharp; always clamped to MIN_FADE_ALPHA.
function Layout.EdgeAlphaForIndex(iconIndex, maxVisible, fadeAmount)
    if not fadeAmount or fadeAmount <= 0 then return 1 end
    local visualCenterIndex = (maxVisible + 1) / 2
    local distFromVisualCenter = math_abs((iconIndex + 1) - visualCenterIndex)
    local halfSpan = math_max(1, (maxVisible - 1) / 2)
    local normDist = math_max(0, math_min(1, distFromVisualCenter / halfSpan))
    local base = math_cos(normDist * math_pi / 2)
    local power = fadeAmount / FADE_CURVE_UNIT
    return math_max(MIN_FADE_ALPHA, base ^ power)
end
