local _, addon = ...

local STRINGS = {
    enUS = { "Reset Position", "Rescan", "Short Name", "Favorite Marker", "Cooldown Text" },
    deDE = { "Position zurücksetzen", "Erneut suchen", "Kurzname", "Favoritenmarkierung", "Abklingzeittext" },
    frFR = {
        "Réinitialiser la position",
        "Analyser à nouveau",
        "Nom court",
        "Marqueur de favori",
        "Texte de recharge",
    },
    esES = {
        "Restablecer posición",
        "Volver a buscar",
        "Nombre corto",
        "Marcador de favorito",
        "Texto de reutilización",
    },
    ptBR = { "Redefinir posição", "Verificar novamente", "Nome curto", "Marcador de favorito", "Texto de recarga" },
    ruRU = {
        "Сбросить позицию",
        "Повторить поиск",
        "Краткое название",
        "Метка избранного",
        "Текст восстановления",
    },
    koKR = {
        "위치 초기화",
        "다시 검색",
        "짧은 이름",
        "즐겨찾기 표시",
        "재사용 대기시간 글자",
    },
    zhCN = { "重置位置", "重新扫描", "简称", "收藏标记", "冷却文字" },
    zhTW = { "重置位置", "重新掃描", "簡稱", "收藏標記", "冷卻文字" },
}
local KEYS = {
    "PLU_PORTAL_RESET_POSITION",
    "PLU_PORTAL_RESCAN",
    "PLU_PORTAL_SHORT_LABEL",
    "PLU_PORTAL_FAVORITE_MARKER",
    "PLU_PORTAL_TIMER",
}

local locale = GetLocale()
if locale == "esMX" then
    locale = "esES"
end
for index, key in ipairs(KEYS) do
    addon.L[key] = (STRINGS[locale] or STRINGS.enUS)[index]
end
