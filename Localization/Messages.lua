local _, addon = ...

local STRINGS = {
    enUS = {
        "Portal settings were created by an unsupported version. They have been left unchanged.",
        "Portal is waiting for a safe initialization state.",
        "Standalone settings are separate from Orbit profiles in this preview.",
        "Using Orbit profile settings. Standalone migration is not enabled in this preview.",
    },
    deDE = {
        "Die Portal-Einstellungen wurden mit einer nicht unterstützten Version erstellt. Sie bleiben unverändert.",
        "Portal wartet auf einen sicheren Zustand zur Initialisierung.",
        "In dieser Vorschau sind eigenständige Einstellungen von Orbit-Profilen getrennt.",
        "Orbit-Profileinstellungen werden verwendet. Die Migration ist in dieser Vorschau nicht aktiviert.",
    },
    frFR = {
        "Les paramètres de Portal proviennent d'une version non prise en charge. Ils restent inchangés.",
        "Portal attend un état permettant une initialisation sûre.",
        "Dans cet aperçu, les paramètres autonomes sont distincts des profils Orbit.",
        "Utilisation du profil Orbit. La migration autonome n'est pas activée dans cet aperçu.",
    },
    esES = {
        "Los ajustes de Portal se crearon con una versión no compatible. No se han modificado.",
        "Portal espera un estado seguro para inicializarse.",
        "En esta vista previa, los ajustes independientes están separados de los perfiles de Orbit.",
        "Se usa el perfil de Orbit. La migración independiente no está habilitada en esta vista previa.",
    },
    ptBR = {
        "As configurações do Portal foram criadas por uma versão incompatível. Elas não foram alteradas.",
        "O Portal está aguardando um estado seguro para inicializar.",
        "Nesta prévia, as configurações independentes são separadas dos perfis do Orbit.",
        "Usando o perfil do Orbit. A migração independente não está ativada nesta prévia.",
    },
    ruRU = {
        "Настройки Portal созданы неподдерживаемой версией. Они оставлены без изменений.",
        "Portal ожидает безопасных условий для инициализации.",
        "В этой предварительной версии отдельные настройки не связаны с профилями Orbit.",
        "Используются настройки профиля Orbit. Перенос отдельных настроек в этой версии не включён.",
    },
    koKR = {
        "지원하지 않는 버전에서 만든 Portal 설정입니다. 설정을 변경하지 않았습니다.",
        "Portal이 안전하게 초기화할 수 있는 상태를 기다리고 있습니다.",
        "이 미리보기에서는 독립 설정과 Orbit 프로필이 분리되어 있습니다.",
        "Orbit 프로필 설정을 사용합니다. 이 미리보기에서는 독립 설정 이전을 지원하지 않습니다.",
    },
    zhCN = {
        "Portal 设置由不受支持的版本创建，已保留原样。",
        "Portal 正在等待可安全初始化的状态。",
        "此预览版的独立设置与 Orbit 配置文件分开保存。",
        "正在使用 Orbit 配置文件设置。此预览版尚未启用独立设置迁移。",
    },
    zhTW = {
        "Portal 設定由不支援的版本建立，已保留原樣。",
        "Portal 正在等待可安全初始化的狀態。",
        "此預覽版的獨立設定與 Orbit 設定檔分開儲存。",
        "正在使用 Orbit 設定檔設定。此預覽版尚未啟用獨立設定移轉。",
    },
}
local KEYS = {
    "MSG_PORTAL_UNSUPPORTED_STORE",
    "MSG_PORTAL_NOT_READY",
    "MSG_PORTAL_STANDALONE_SETTINGS",
    "MSG_PORTAL_LEGACY_SETTINGS",
}

local locale = GetLocale()
if locale == "esMX" then
    locale = "esES"
end
for index, key in ipairs(KEYS) do
    addon.L[key] = (STRINGS[locale] or STRINGS.enUS)[index]
end
