--[[
    UI/Fonts.lua
    ---------------------------------------------------------------------
    The old addon's "FontString:SetText(): Font not set" error came from a
    FontString being created with no template and no explicit SetFont
    call before something tried to use it. The fix here isn't a patch on
    one call site - it's that nothing in this addon is allowed to create a
    bare, unstyled FontString at all: everything goes through
    Jui.UI:CreateText() (in Components.lua), which always calls
    Jui.Fonts:Apply() as part of construction, before the FontString is
    handed back to the caller. There is no code path that produces an
    unstyled FontString.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.Fonts = {}

-- Named sizes, matching the "Title / Header / Body / Small / Number" list
-- from the spec.
local SIZES = {
    Title  = 20,
    Header = 15,
    Body   = 12,
    Small  = 11,
    Number = 13,
}
Jui.Fonts.Sizes = SIZES

-- Always sets an explicit font before anything else touches the
-- FontString - this is the one function in the whole addon allowed to
-- leave a FontString in a "just created" state, because it immediately
-- fixes that state itself.
function Jui.Fonts:Apply(fontString, sizeName, flags)
    if not fontString then return end
    local size = SIZES[sizeName] or sizeName or SIZES.Body

    fontString:SetFont("Fonts\\FRIZQT__.TTF", size, flags or "THINOUTLINE")
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)

    return fontString
end
