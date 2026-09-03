--[[
    UI/Theme.lua
    ---------------------------------------------------------------------
    Every color used anywhere in the UI lives here. No module or
    component should hard-code an RGB triple - they pull from Jui.Theme
    so the whole addon stays visually consistent and re-themeable from one
    place (the accent color picker on the Interface page mutates
    Jui.Theme.accent in place, which every already-built widget re-reads
    live rather than needing to be rebuilt).
--]]

local addonName, ns = ...

Jui = Jui or {}

local defaultAccent = {1, 0.82, 0} -- classic Blizzard gold

Jui.Theme = {
    -- Backgrounds
    bgWindow    = {0.045, 0.045, 0.05, 1},
    bgPanel     = {0.065, 0.065, 0.07, 1},
    bgInset     = {0.035, 0.035, 0.04, 1},
    bgCard      = {0.08, 0.08, 0.09, 1},

    -- Borders (kept subtle - the framework favors shade differences over
    -- heavy drawn boxes)
    border      = {0.2, 0.2, 0.22, 0.5},
    borderSoft  = {0.16, 0.16, 0.18, 0.35},

    -- Text
    textPrimary = {0.9, 0.9, 0.92},
    textSecond  = {0.58, 0.58, 0.62},
    textFaint   = {0.4, 0.4, 0.43},

    -- Semantic accents (section 11 of the spec)
    accent      = defaultAccent, -- Jui accent / selected
    success     = {0.42, 0.7, 0.36}, -- enabled / healthy
    warning     = {0.85, 0.6, 0.25}, -- warning
    danger      = {0.82, 0.35, 0.32}, -- disabled / error
    info        = {0.62, 0.5, 0.85}, -- secondary information (purple)
    inactive    = {0.45, 0.45, 0.48}, -- grey
}

-- Applies a saved custom accent color on top of the default, if one
-- exists. Called from Core/Init.lua's lifecycle, before UI:Initialize()
-- builds anything - so every widget that reads Jui.Theme.accent at
-- creation time already sees the user's chosen color, no re-skin pass
-- needed afterward.
function Jui.Theme:ApplySavedAccent()
    local db = Jui.Database:Get()
    local saved = db.profile.accentColor
    if saved and saved[1] then
        self.accent[1], self.accent[2], self.accent[3] = saved[1], saved[2], saved[3]
    end
end

-- Mutates the accent table in place (rather than replacing it) so every
-- widget that captured a reference to Jui.Theme.accent at creation time -
-- which is most of them, via unpack(Jui.Theme.accent) - immediately picks
-- up the new value on its next redraw.
function Jui.Theme:SetAccent(r, g, b)
    self.accent[1], self.accent[2], self.accent[3] = r, g, b
    local db = Jui.Database:Get()
    db.profile.accentColor = {r, g, b}
end

function Jui.Theme:ResetAccent()
    self:SetAccent(defaultAccent[1], defaultAccent[2], defaultAccent[3])
end
