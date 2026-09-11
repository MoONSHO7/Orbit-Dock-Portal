local _, addon = ...

addon.PortalDefaults = {
    Enabled = true,
    IconSize = 32,
    Spacing = 5,
    MaxVisible = 9,
    HideLongCooldowns = true,
    EnableKeyboardSearch = true,
    FadeEffect = 0,
    Compactness = 0,
    Animation = 0,
    Favorites = {},
    EnabledCategories = {},
    Anchor = false,
    Position = { point = "LEFT", x = 8, y = 0 },
    ComponentPositions = {
        DungeonScore = { anchorX = "CENTER", anchorY = "BOTTOM", offsetX = 0, offsetY = -2, justifyH = "CENTER" },
        DungeonShort = { anchorX = "CENTER", anchorY = "TOP", offsetX = 0, offsetY = 2, justifyH = "CENTER" },
        FavouriteStar = { anchorX = "RIGHT", anchorY = "TOP", offsetX = 1, offsetY = 1, justifyH = "RIGHT" },
        Timer = { anchorX = "CENTER", anchorY = "CENTER", offsetX = 0, offsetY = 0, justifyH = "CENTER" },
    },
    DisabledComponents = { "DungeonShort" },
}
