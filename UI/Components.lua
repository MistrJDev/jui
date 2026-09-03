--[[
    UI/Components.lua
    ---------------------------------------------------------------------
    The shared widget library (section 12 of the spec). Every panel,
    button, checkbox, slider, dropdown, etc. anywhere in the addon is
    built from these, so every module gets the same visual language for
    free instead of re-implementing its own.

    All backgrounds use Interface\Buttons\WHITE8X8 - a flat 1x1 white
    texture tinted via backdrop color - and nothing else. An earlier
    version of this addon used a custom rounded-corner technique built
    from masked texture pieces, which rendered as a single broken solid
    block in the live client. WHITE8X8 is the simplest, most
    well-established background texture in the game; corners are square
    everywhere as a deliberate trade-off for reliability.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.UI = Jui.UI or {}

local C = Jui.Theme

----------------------------------------------------------------------
-- Panel / Divider
----------------------------------------------------------------------
function Jui.UI:CreatePanel(parent, fillColor, borderColor, borderThickness)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if borderColor then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = borderThickness or 1,
        })
        f:SetBackdropBorderColor(unpack(borderColor))
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    end
    f:SetBackdropColor(unpack(fillColor))
    return f
end

function Jui.UI:CreateDivider(parent)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetHeight(1)
    tex:SetColorTexture(unpack(C.borderSoft))
    return tex
end

----------------------------------------------------------------------
-- Text - the only way a FontString gets created anywhere in this addon.
-- See UI/Fonts.lua for why that matters.
----------------------------------------------------------------------
function Jui.UI:CreateText(parent, sizeName, colorTable)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Jui.Fonts:Apply(fs, sizeName)
    fs:SetTextColor(unpack(colorTable or C.textPrimary))
    return fs
end

----------------------------------------------------------------------
-- Header / Section - page and card titles
----------------------------------------------------------------------
function Jui.UI:CreateHeader(parent, title)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(30)

    local text = self:CreateText(header, "Header", C.textPrimary)
    text:SetPoint("BOTTOMLEFT", 0, 6)
    text:SetText(title)
    header.Text = text

    local line = self:CreateDivider(header)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    header.Line = line

    return header
end

-- A settings card: flat "well" background (no border - separation is the
-- shade difference against its parent), small muted uppercase title, and
-- an optional description paragraph.
-- A settings card: no border - separation comes from a subtly darker
-- "well" shade against the content panel behind it, not a drawn box.
-- Title is a small muted uppercase label with an optional description
-- paragraph beneath it. width defaults to 440 (matching most cards) but
-- MUST be set before the description's wrapped height is measured below -
-- setting it via a separate :SetSize() call after CreateSection returns
-- (the old pattern) left the description without a wrap width at the
-- moment GetStringHeight() ran, so it always reported a too-small height
-- and everything below it - the divider, the sliders, the labels -
-- rendered too high, overlapping text that only wrapped to its real,
-- multi-line height once layout caught up.
function Jui.UI:CreateSection(parent, title, desc, width)
    local group = self:CreatePanel(parent, C.bgInset, nil)
    group:SetWidth(width or 440)

    group.Title = self:CreateText(group, "Small", C.textSecond)
    group.Title:SetPoint("TOPLEFT", 14, -10)
    group.Title:SetText(title:upper())

    local dividerY = -26
    if desc and desc ~= "" then
        group.Desc = self:CreateText(group, "Small", C.textFaint)
        group.Desc:SetPoint("TOPLEFT", group.Title, "BOTTOMLEFT", 0, -4)
        group.Desc:SetPoint("RIGHT", -14, 0)
        group.Desc:SetJustifyH("LEFT")
        group.Desc:SetText(desc)
        dividerY = dividerY - group.Desc:GetStringHeight() - 2
    end

    local line = self:CreateDivider(group)
    line:SetPoint("TOPLEFT", 14, dividerY)
    line:SetPoint("TOPRIGHT", -14, dividerY)
    group.ContentTop = dividerY - 12 -- a sensible y-offset for the first control

    return group
end

----------------------------------------------------------------------
-- Status pill - "● ENABLED" / "● OFF" style indicator
----------------------------------------------------------------------
function Jui.UI:CreateStatus(parent, isOn)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(90, 16)

    local dot = f:CreateTexture(nil, "ARTWORK")
    dot:SetSize(7, 7)
    dot:SetPoint("LEFT", 0, 0)

    local text = self:CreateText(f, "Small", C.textSecond)
    text:SetPoint("LEFT", dot, "RIGHT", 6, 0)

    function f:SetOn(on)
        if on then
            dot:SetColorTexture(unpack(C.success))
            text:SetText("ENABLED")
            text:SetTextColor(unpack(C.success))
        else
            dot:SetColorTexture(unpack(C.inactive))
            text:SetText("OFF")
            text:SetTextColor(unpack(C.textFaint))
        end
    end

    f:SetOn(isOn)
    return f
end

----------------------------------------------------------------------
-- Button
----------------------------------------------------------------------
-- style: "primary" (filled accent, dark text, for the one important
-- action on a page) or nil/"default" (flat inset, light text).
function Jui.UI:CreateButton(parent, label, style)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(90, 24)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    btn.Text = btn:CreateFontString(nil, "OVERLAY")
    btn.Text:SetAllPoints()
    btn.Text:SetJustifyH("CENTER")

    -- The font MUST be set before SetText is ever called on a freshly
    -- created, template-less FontString - it has no font at all until
    -- one is explicitly applied, and calling SetText first throws
    -- "FontString:SetText(): Font not set". Both style branches below set
    -- a font; SetText only runs once, after either branch has run.
    if style == "primary" then
        btn:SetBackdropColor(unpack(C.accent))
        -- Deliberately no outline/shadow: this text is dark-on-bright, so
        -- a black outline just smears into the equally-dark fill instead
        -- of adding contrast - plain crisp text is what actually reads
        -- clearly here.
        btn.Text:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
        btn.Text:SetShadowColor(0, 0, 0, 0)
        btn.Text:SetTextColor(0.1, 0.08, 0.02)
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 0.9, 0.4, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(C.accent)) end)
    else
        btn:SetBackdropColor(unpack(C.bgInset))
        btn:SetBackdropBorderColor(unpack(C.borderSoft))
        Jui.Fonts:Apply(btn.Text, "Small")
        btn.Text:SetTextColor(unpack(C.textSecond))
        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.borderSoft)) end)
    end

    btn.Text:SetText(label)

    return btn
end

----------------------------------------------------------------------
-- Checkbox (a toggle switch, matching the addon's existing visual style)
----------------------------------------------------------------------
-- getter/setter: getter() -> bool, setter(bool) called on toggle. Kept as
-- plain functions (rather than a db/key pair) so this same component can
-- back both per-module settings and the module-registry Enable/Disable
-- toggles on the Overview page.
function Jui.UI:CreateCheckbox(parent, label, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 20)

    local trackW, trackH, knobSize, pad = 32, 15, 11, 2
    local onX, offX = trackW - knobSize - pad, pad

    local track = CreateFrame("Frame", nil, container, "BackdropTemplate")
    track:SetSize(trackW, trackH)
    track:SetPoint("LEFT", 0, 0)
    track:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    function track:SetColor(r, g, b, a) self:SetBackdropColor(r, g, b, a) end
    track:SetColor(unpack(C.bgInset))

    local knob = CreateFrame("Frame", nil, track, "BackdropTemplate")
    knob:SetSize(knobSize, knobSize)
    knob:SetFrameLevel(track:GetFrameLevel() + 1)
    knob:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    function knob:SetColor(r, g, b, a) self:SetBackdropColor(r, g, b, a) end
    knob:SetColor(0.88, 0.85, 0.86, 1)
    knob:SetPoint("LEFT", track, "LEFT", offX, 0)

    local labelText = self:CreateText(container, "Small", C.textSecond)
    labelText:SetPoint("LEFT", track, "RIGHT", 8, 0)
    labelText:SetText(label)

    local function Refresh(animate)
        local checked = getter() and true or false

        if checked then
            track:SetColor(unpack(C.success))
            labelText:SetTextColor(unpack(C.textPrimary))
        else
            track:SetColor(unpack(C.bgInset))
            labelText:SetTextColor(unpack(C.textSecond))
        end

        local targetX = checked and onX or offX
        if not animate then
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", track, "LEFT", targetX, 0)
            return
        end

        local _, _, _, curX = knob:GetPoint(1)
        local startX = curX or targetX
        local elapsed = 0
        local duration = 0.1
        knob:SetScript("OnUpdate", function(self, delta)
            elapsed = elapsed + delta
            local t = math.min(elapsed / duration, 1)
            self:ClearAllPoints()
            self:SetPoint("LEFT", track, "LEFT", startX + (targetX - startX) * t, 0)
            if t >= 1 then self:SetScript("OnUpdate", nil) end
        end)
    end

    local hitArea = CreateFrame("Button", nil, container)
    hitArea:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 4)
    hitArea:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 4, -4)
    hitArea:RegisterForClicks("AnyUp")
    hitArea:SetScript("OnClick", function()
        setter(not (getter() and true or false))
        Refresh(true)
    end)

    container:SetScript("OnShow", function() Refresh(false) end)
    container.Refresh = function() Refresh(false) end
    Refresh(false) -- same reason as the slider fix above: rebuilt widgets
                    -- are created already shown, so OnShow can't be relied
                    -- on to run this the first time.

    return container
end

----------------------------------------------------------------------
-- Slider - a real native Slider widget under a flat skin, with
-- right-click-to-type support.
----------------------------------------------------------------------
local sliderNameCounter = 0

local function ShowSliderInput(slider, label, minV, maxV, getValue, setValue)
    StaticPopupDialogs["JUI_SLIDER_INPUT"] = {
        text = string.format("|cffffd100%s|r\n\nEnter a value (%d - %d):", label, minV, maxV),
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 8,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if eb then
                eb:SetText(tostring(math.floor(getValue() + 0.5)))
                eb:HighlightText()
                eb:SetFocus()
            end
        end,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local num = tonumber(eb and eb:GetText())
            if num then setValue(Jui.Utils:Clamp(num, minV, maxV)) end
        end,
        EditBoxOnEnterPressed = function(self)
            local num = tonumber(self:GetText())
            if num then setValue(Jui.Utils:Clamp(num, minV, maxV)) end
            local parent = self:GetParent()
            if parent then parent:Hide() end
        end,
        EditBoxOnEscapePressed = function(self)
            local parent = self:GetParent()
            if parent then parent:Hide() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("JUI_SLIDER_INPUT")
end

-- getter/setter follow the same plain-function convention as the checkbox.
function Jui.UI:CreateSlider(parent, label, minV, maxV, getter, setter)
    sliderNameCounter = sliderNameCounter + 1
    local name = "JuiSlider" .. sliderNameCounter

    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(160)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)

    local valueText = _G[name .. "Text"]
    _G[name .. "Low"]:Hide()
    _G[name .. "High"]:Hide()

    local labelText = s:CreateFontString(nil, "OVERLAY")
    labelText:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 5)
    labelText:SetJustifyH("LEFT")
    Jui.Fonts:Apply(labelText, "Small")
    labelText:SetTextColor(unpack(C.textSecond))
    labelText:SetText(label)

    valueText:ClearAllPoints()
    valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 5)
    valueText:SetJustifyH("RIGHT")
    Jui.Fonts:Apply(valueText, "Small")

    local function UpdateLabel(v)
        valueText:SetText(string.format("|cffffd100%d|r", math.floor(v)))
    end

    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        UpdateLabel(value)
        setter(value)
    end)

    -- Sliders used to be built once, so OnShow (their first real
    -- hidden->shown transition) reliably ran this initialization. Since
    -- tabs now rebuild their widgets fresh on every visit, a slider is
    -- created already in the shown state - no transition happens, so
    -- OnShow doesn't fire, and the value text was staying blank forever.
    -- Set it synchronously right here instead; OnShow is kept as a
    -- harmless no-op fallback in case something does trigger it later.
    local function InitializeValue()
        local v = getter() or minV
        s:SetValue(v)
        UpdateLabel(v)
    end
    s:SetScript("OnShow", InitializeValue)
    InitializeValue()

    s:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            ShowSliderInput(s, label, minV, maxV, getter, function(v) s:SetValue(v) end)
        end
    end)

    return s
end

----------------------------------------------------------------------
-- Dropdown
----------------------------------------------------------------------
-- options = { {value=..., text=...}, ... }. getter/setter as above.
function Jui.UI:CreateDropdown(parent, label, options, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(160, 42)

    local title = self:CreateText(container, "Small", C.textSecond)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(160, 22)
    btn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(unpack(C.bgInset))
    btn:SetBackdropBorderColor(unpack(C.borderSoft))

    btn.Text = self:CreateText(btn, "Small", C.textPrimary)
    btn.Text:SetPoint("LEFT", 8, 0)
    btn.Text:SetPoint("RIGHT", -18, 0)
    btn.Text:SetJustifyH("LEFT")

    local arrow = self:CreateText(btn, "Small", C.accent)
    arrow:SetPoint("RIGHT", -7, 0)
    arrow:SetText("\226\150\190") -- ▾

    local list = self:CreatePanel(container, C.bgCard, C.accent, 1)
    list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    list:SetWidth(160)
    list:SetFrameStrata("DIALOG")
    list:Hide()

    local function Select(value, text)
        setter(value)
        btn.Text:SetText(text)
        list:Hide()
    end

    local rowHeight = 20
    for i, opt in ipairs(options) do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(160, rowHeight)
        row:SetPoint("TOP", 0, -(i - 1) * rowHeight)

        row.Text = self:CreateText(row, "Small", C.textPrimary)
        row.Text:SetPoint("LEFT", 8, 0)
        row.Text:SetText(opt.text)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.2)

        row:SetScript("OnClick", function() Select(opt.value, opt.text) end)
    end
    list:SetHeight(#options * rowHeight + 4)

    btn:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else list:Show() end
    end)
    local function RefreshLabel()
        local current = getter()
        for _, opt in ipairs(options) do
            if opt.value == current then
                btn.Text:SetText(opt.text)
                return
            end
        end
        if options[1] then btn.Text:SetText(options[1].text) end
    end
    btn:SetScript("OnShow", RefreshLabel)
    RefreshLabel() -- same reason as the slider/checkbox fixes: rebuilt
                    -- widgets are created already shown, so OnShow alone
                    -- can't be relied on to run this the first time.
    btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.borderSoft)) end)

    return container, btn
end

----------------------------------------------------------------------
-- Input - a simple text entry box
----------------------------------------------------------------------
function Jui.UI:CreateInput(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 80, 22)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(unpack(C.bgInset))
    box:SetBackdropBorderColor(unpack(C.borderSoft))
    box:SetAutoFocus(false)
    box:SetTextInsets(6, 6, 0, 0)
    Jui.Fonts:Apply(box, "Small")
    box:SetTextColor(unpack(C.textPrimary))
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.borderSoft)) end)
    return box
end

----------------------------------------------------------------------
-- Tooltip helper (used the same way across every component above)
----------------------------------------------------------------------
function Jui.UI:AttachTooltip(widget, title, desc)
    if not desc or desc == "" then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(desc, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
