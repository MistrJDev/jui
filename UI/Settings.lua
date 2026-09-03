--[[
    UI/Settings.lua
    ---------------------------------------------------------------------
    Every module's settings page is built through Jui.UI.Settings, which
    handles the two states a module page can be in (section 34-35 of the
    spec) so no individual module has to reimplement them:

      - Disabled: an explanatory line + an Enable button, instead of a
        blank page. This directly targets the old addon's "Capping tab ->
        blank content" bug, which happened because the tab's own build
        code silently failed (a deleted event-frame declaration threw an
        uncaught error) rather than the framework ever guaranteeing a page
        has *something* to show.
      - Enabled: the module's own CreateSettings(parent) content, with a
        standard header + Enable/Disable status above it.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.UI = Jui.UI or {}
Jui.UI.Settings = {}

local C = Jui.Theme

-- Registers one module's settings page under the "gameplay" or "auras"
-- nav group. Called once per module, from that module's own file.
function Jui.UI.Settings:RegisterModulePage(moduleId, label, group)
    Jui.UI.Navigation:AddPage(moduleId, label, group, function(parent)
        local header = Jui.UI:CreateHeader(parent, label)
        header:SetPoint("TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", 0, 0)

        local status = Jui.UI:CreateStatus(header, Jui.Modules:IsEnabled(moduleId))
        status:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 8)

        -- body is NOT stretched down to parent's bottom - inside a scroll
        -- frame, parent (the scroll child) needs to be sized to fit its
        -- content, not the other way around. body's own height comes from
        -- whatever the module's CreateSettings sets on it below.
        local body = CreateFrame("Frame", nil, parent)
        body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -14)
        body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -14)
        body:SetHeight(1)

        local function Rebuild()
            for _, child in ipairs({body:GetChildren()}) do
                child:Hide()
                child:SetParent(nil)
            end
            for _, region in ipairs({body:GetRegions()}) do
                region:Hide()
            end

            status:SetOn(Jui.Modules:IsEnabled(moduleId))

            if Jui.Modules:IsEnabled(moduleId) then
                local def = Jui.Modules:Get(moduleId)
                if def and def.CreateSettings then
                    -- Same reasoning as the pcall wrapper in Navigation's
                    -- ShowPage: a module's CreateSettings failing partway
                    -- through used to leave a silently truncated page
                    -- (WoW hides Lua errors by default) with no visible
                    -- sign anything went wrong.
                    local ok, err = pcall(def.CreateSettings, def, body)
                    if not ok then
                        local errorText = Jui.UI:CreateText(body, "Small", C.textFaint)
                        errorText:SetPoint("TOPLEFT", 0, -4)
                        errorText:SetPoint("RIGHT", 0, 0)
                        errorText:SetJustifyH("LEFT")
                        errorText:SetText("|cffff6b6b" .. label .. " failed to build:|r\n" .. tostring(err))
                        body:SetHeight(math.max(errorText:GetStringHeight() + 20, 60))
                        geterrorhandler()(err)
                    end
                end
            else
                local msg = Jui.UI:CreateText(body, "Body", C.textSecond)
                msg:SetPoint("TOPLEFT", 0, -4)
                msg:SetText(label .. " is currently disabled.")

                local enableBtn = Jui.UI:CreateButton(body, "Enable", "primary")
                enableBtn:SetPoint("TOPLEFT", msg, "BOTTOMLEFT", 0, -12)
                enableBtn:SetScript("OnClick", function()
                    Jui.Modules:Enable(moduleId)
                    Rebuild()
                end)
                body:SetHeight(70)
            end

            -- body's height is set by whichever branch above ran (either
            -- the module's own CreateSettings or the disabled-state
            -- fallback); this frame (the scroll child) sizes itself to
            -- match, which is what actually controls the scroll range.
            parent:SetHeight(header:GetHeight() + 14 + body:GetHeight())
        end

        parent.Rebuild = Rebuild
        Rebuild()
    end)
end

-- A small "no battleground active" style empty-state (section 35),
-- reusable by any module whose display only makes sense in a specific
-- context.
function Jui.UI.Settings:CreateEmptyState(parent, message, hint)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()

    local msg = Jui.UI:CreateText(f, "Body", C.textSecond)
    msg:SetPoint("TOP", 0, -30)
    msg:SetText(message)

    if hint then
        local hintText = Jui.UI:CreateText(f, "Small", C.textFaint)
        hintText:SetPoint("TOP", msg, "BOTTOM", 0, -8)
        hintText:SetWidth(360)
        hintText:SetJustifyH("CENTER")
        hintText:SetText(hint)
    end

    return f
end

----------------------------------------------------------------------
-- The Interface page (section 15) - global window settings, not tied to
-- any one module, so it's registered here rather than as a module page.
----------------------------------------------------------------------
Jui.UI.Navigation:AddPage("interface", "Interface", "core", function(parent)
    local header = Jui.UI:CreateHeader(parent, "Interface")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)

    local windowGroup = Jui.UI:CreateSection(parent, "Main Window")
    windowGroup:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -14)
    windowGroup:SetSize(650, 90)

    local scaleSlider = Jui.UI:CreateSlider(windowGroup, "Scale", 50, 200,
        function() return (Jui.Database:Get().profile.scale or 1) * 100 end,
        function(v)
            Jui.Database:Get().profile.scale = v / 100
            Jui.UI:ApplyScale()
        end)
    scaleSlider:SetPoint("TOPLEFT", 15, windowGroup.ContentTop)

    local themeGroup = Jui.UI:CreateSection(parent, "Theme",
        "Pick a new accent color for the whole window.")
    themeGroup:SetPoint("TOPLEFT", windowGroup, "BOTTOMLEFT", 0, -14)
    themeGroup:SetSize(650, 90)

    local swatch = CreateFrame("Button", nil, themeGroup, "BackdropTemplate")
    swatch:SetSize(60, 22)
    swatch:SetPoint("TOPLEFT", 15, themeGroup.ContentTop)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(unpack(C.borderSoft))

    local function RefreshSwatch()
        swatch:SetBackdropColor(unpack(C.accent))
    end
    swatch:SetScript("OnShow", RefreshSwatch)

    swatch:SetScript("OnClick", function()
        local r, g, b = unpack(C.accent)
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                Jui.Theme:SetAccent(nr, ng, nb)
                RefreshSwatch()
            end,
            cancelFunc = function(prev)
                if prev then
                    Jui.Theme:SetAccent(prev.r, prev.g, prev.b)
                    RefreshSwatch()
                end
            end,
        })
    end)

    local resetBtn = Jui.UI:CreateButton(themeGroup, "Reset")
    resetBtn:SetPoint("LEFT", swatch, "RIGHT", 12, 0)
    resetBtn:SetScript("OnClick", function()
        Jui.Theme:ResetAccent()
        RefreshSwatch()
    end)

    local note = Jui.UI:CreateText(themeGroup, "Small", C.textFaint)
    note:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    note:SetPoint("RIGHT", -15, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Applies immediately across the whole window.")

    parent:SetHeight(header:GetHeight() + 14 + windowGroup:GetHeight() + 14 + themeGroup:GetHeight())
end)
