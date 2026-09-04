--[[
    Core/Database.lua
    ---------------------------------------------------------------------
    JuiDB is now versioned and structured (profile / modules / per-module
    tables) instead of one flat bag of keys. Existing installs get their
    recognisable old settings copied across rather than reset.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.Database = {}

local CURRENT_VERSION = 1

local DEFAULTS = {
    version = CURRENT_VERSION,

    profile = {
        scale = 1,
        accentColor = {1, 0.82, 0},
    },

    modules = {
        capping = false,
        queueTimer = true,
        winrate = true,
        lossOfControl = true,
        raidAuras = false,
        playerAuras = false,
    },

    lossOfControl = {
        x = 0,
        y = -60,
        size = 40,
        typeTextSize = 16,
        counterTextSize = 18,
        showTypeText = true,
        showCounter = true,
        typeTextColor = {1, 0.25, 0.2},
    },

    queueTimer = {
        x = 0,
        y = -300,
        fontSize = 18,
    },

    winrate = {
        x = -60,
        y = 15,
        size = 12,
    },

    raidAuras = {
        tooltips = true,
        buffSize = 28,
        debuffSize = 20,
        maxBuffs = 6,
        maxDebuffs = 3,
        buffsPerRow = 3,
        debuffsPerRow = 5,
        buffsMine = true,
        buffsShortOnly = false,
        showImportantBuffs = true,
        buffNumbers = true,
        buffCenterStacks = false,
        debuffsDispellable = false,
        debuffsShortOnly = false,
        dispelColors = true,
        debuffNumbers = false,
        debuffCenterStacks = false,
        showDefensives = true,
        dispelScale = 1.25,
        debuffSide = "LEFT",
        otherSize = 40,
        otherPoint = "CENTER",
        otherX = -2,
        otherY = 2,
        durationTextSize = 110,
        countTextSize = 110,
    },

    playerAuras = {
        tooltips = true,
        iconSize = 30,
        durationTextSize = 100,
        countTextSize = 100,
        showBuffs = true,
        showDebuffs = true,
        showEnchants = true,
        iconSpacing = 2,
        enchantColor = {1, 0.82, 0},
    },

    capping = {
        locked = true,
        scale = 1,
        x = 0,
        y = 220,
        maxBars = 5,
        textSize = 11,
        growDirection = "DOWN",
        showMarker = true,
    },
}
Jui.Database.Defaults = DEFAULTS

-- Recognises the addon's pre-1.0 flat JuiDB (a single table of prefixed
-- keys like raidAurasBuffSize / locX / uiScale) and copies over anything
-- that still maps cleanly onto the new structure. Anything that doesn't
-- map (removed features, renamed keys) is just left behind - the relevant
-- module falls back to its own default instead.
local function MigrateFromLegacy(old, db)
    if type(old) ~= "table" then return end

    -- A couple of unmistakable legacy-only keys - if neither is present
    -- this probably isn't the old flat format at all, so don't guess.
    if old.locX == nil and old.raidAurasBuffSize == nil and old.uiScale == nil then
        return
    end

    if old.uiScale then db.profile.scale = old.uiScale / 100 end
    if old.uiAccentColor then db.profile.accentColor = old.uiAccentColor end

    if old.locX then db.lossOfControl.x = old.locX end
    if old.locY then db.lossOfControl.y = old.locY end
    if old.locSize then db.lossOfControl.size = old.locSize end

    if old.qX then db.queueTimer.x = old.qX end
    if old.qY then db.queueTimer.y = old.qY end
    if old.qFontSize then db.queueTimer.fontSize = old.qFontSize end

    if old.wrX then db.winrate.x = old.wrX end
    if old.wrY then db.winrate.y = old.wrY end
    if old.wrSize then db.winrate.size = old.wrSize end

    local raidMap = {
        raidAurasTooltips = "tooltips", raidAurasBuffSize = "buffSize",
        raidAurasDebuffSize = "debuffSize", raidAurasMaxBuffs = "maxBuffs",
        raidAurasMaxDebuffs = "maxDebuffs", raidAurasBuffsPerRow = "buffsPerRow",
        raidAurasDebuffsPerRow = "debuffsPerRow", raidAurasBuffsMine = "buffsMine",
        raidAurasBuffsShortOnly = "buffsShortOnly", raidAurasShowImportantBuffs = "showImportantBuffs",
        raidAurasBuffNumbers = "buffNumbers", raidAurasBuffCenterStacks = "buffCenterStacks",
        raidAurasDebuffsDispellable = "debuffsDispellable", raidAurasDebuffsShortOnly = "debuffsShortOnly",
        raidAurasDispelColors = "dispelColors", raidAurasDebuffNumbers = "debuffNumbers",
        raidAurasDebuffCenterStacks = "debuffCenterStacks", raidAurasShowDefensives = "showDefensives",
        raidAurasDispelScale = "dispelScale", raidAurasDebuffSide = "debuffSide",
        raidAurasOtherSize = "otherSize", raidAurasOtherPoint = "otherPoint",
        raidAurasOtherX = "otherX", raidAurasOtherY = "otherY",
        raidAurasDurationTextSize = "durationTextSize", raidAurasCountTextSize = "countTextSize",
    }
    for oldKey, newKey in pairs(raidMap) do
        if old[oldKey] ~= nil then db.raidAuras[newKey] = old[oldKey] end
    end
    if old.raidAurasEnabled ~= nil then db.modules.raidAuras = old.raidAurasEnabled end

    local playerMap = {
        playerAurasTooltips = "tooltips", playerAurasIconSize = "iconSize",
        playerAurasDurationTextSize = "durationTextSize", playerAurasCountTextSize = "countTextSize",
    }
    for oldKey, newKey in pairs(playerMap) do
        if old[oldKey] ~= nil then db.playerAuras[newKey] = old[oldKey] end
    end
    if old.playerAurasEnabled ~= nil then db.modules.playerAuras = old.playerAurasEnabled end

    if old.cappingX ~= nil then db.capping.x = old.cappingX end
    if old.cappingY ~= nil then db.capping.y = old.cappingY end
    if old.cappingSize ~= nil then db.capping.scale = (old.cappingSize or 100) / 100 end
    if old.cappingEnabled ~= nil then db.modules.capping = old.cappingEnabled end
end

-- Called once from Core/Init.lua, after ADDON_LOADED. JuiDB is already a
-- restored global by then if this isn't the first-ever load.
function Jui.Database:Initialize()
    local legacy = nil
    if JuiDB and JuiDB.version == nil then
        -- No version field at all - this is either the pre-1.0 flat
        -- format, or a brand new empty table. MigrateFromLegacy itself
        -- checks for recognisable legacy keys before touching anything.
        legacy = JuiDB
    end

    if type(JuiDB) ~= "table" or JuiDB.version == nil then
        JuiDB = Jui.Utils:CopyTable(DEFAULTS)
    end

    Jui.Utils:ApplyDefaults(JuiDB, DEFAULTS)

    if legacy then
        MigrateFromLegacy(legacy, JuiDB)
    end

    JuiDB.version = CURRENT_VERSION
    self.db = JuiDB
end

function Jui.Database:Get()
    return self.db
end
