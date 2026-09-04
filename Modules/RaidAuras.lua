--[[
    RaidAuras.lua
    ---------------------------------------------------------------------
    Party/Raid frame Buffs, Debuffs, and "Other" (important defensive)
    aura display, forked from mirror's Theme/Auras.lua raid-frame system
    and rebuilt as a small, self-contained module that only touches
    Blizzard's native CompactParty*/CompactRaid* frames.

    It uses the client's native AuraContainer/AuraButton widgets (the same
    ones Blizzard's own raid frames use), so there's no manual OnUpdate
    polling of auras - the widgets refresh themselves.
--]]

local addonName, ns = ...
local C = Jui.Theme

-- Declared empty here and assigned inside OnEnable, not at file scope:
-- this file loads before Jui.Database:Initialize() has run, so
-- Jui.Database:Get() would still be nil at this point.
local db
local UpdateTestPreview -- forward-declared: UpdateAllSizes/UpdateAllDispelColors
                          -- (defined well before the test preview section)
                          -- need to call this, and it can't be an upvalue
                          -- to code that runs before its own declaration.
local RaidTest = {isTesting = false, icons = {}} -- same reasoning - referenced
                                                   -- by UpdateAllSizes/UpdateAllDispelColors
                                                   -- long before the test preview
                                                   -- section actually builds it out.

----------------------------------------------------------------------
-- Tunables (ported from mirror; these mirror Blizzard's own defaults
-- for the built-in raid frame aura display)
----------------------------------------------------------------------
local RAID_MAX_BUFFS = 6
local RAID_BUFFS_PER_ROW = 3
local RAID_ICON_GAP = 1
local RAID_MAX_BIG_DEBUFFS = 2
local RAID_MAX_DEFENSIVE = 3

-- Fixed, frame-independent base size the "Other" (defensive) icons are
-- actually created at, and the fixed reference UpdateAllSizes scales
-- relative to. GetOtherSize() below is now a plain absolute value too
-- (matching buffSize/debuffSize) rather than being frame:GetHeight()
-- relative - that relative approach recalculated the target size on every
-- single UpdateAllSizes() call (which fires on every
-- CompactUnitFrame_SetUnit), and raid frame height isn't perfectly stable
-- moment to moment (combat state, layout changes), so the computed target
-- size - and the SetScale() ratio applied to the whole container icon
-- and border together - drifted slightly on nearly every refresh, which
-- read as the icon and its border visibly resizing on their own.
local OTHER_BASE_SIZE = 36

-- Only applied in PvP instances: permanent auras (e.g. Dampening) would
-- otherwise clutter raid frames, but PvE fights routinely have legitimate
-- no-timer debuffs that should stay visible.
local RAID_DEBUFF_MAX_DURATION = 100000
local RAID_BUFF_MAX_DURATION = 100000

local function IsPvpInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "pvp" or instanceType == "arena"
end

-- A handful of buffs that are always worth calling out even when they'd
-- otherwise be crowded out of the normal buff row.
local IMPORTANT_BUFFS = {
    [10060] = true, -- Power Infusion
    [1044] = true, -- Blessing of Freedom
    [210256] = true, -- Blessing of Sanctuary
    [106898] = true, -- Stampeding Roar (No Form)
    [77764] = true, -- Stampeding Roar (Cat)
    [77761] = true, -- Stampeding Roar (Bear)
    [116841] = true, -- Tiger's Lust
    [53563] = true, -- Beacon of Light
    [156910] = true, -- Beacon of Faith
    [200025] = true, -- Beacon of Virtue
    [974] = true, -- Earth Shield
    [383648] = true, -- Earth Shield
    [57934] = true, -- Tricks of the Trade
    [59628] = true -- Tricks of the Trade
}

-- Personal/party defensive cooldowns, force-shown in the "Other" container.
local RAID_DEFENSIVES = {
    [498] = true, -- Divine Protection
    [403876] = true, -- Divine Protection
    [33206] = true, -- Pain Suppression
    [31821] = true, -- Aura Mastery
    [325174] = true, -- Spirit Link Totem
    [108416] = true, -- Dark Pact
    [200183] = true, -- Apotheosis
    [15286] = true, -- Vampiric Embrace
    [125174] = true, -- Touch of Karma
    [97463] = true, -- Rallying Cry
    [5277] = true, -- Evasion
    [187827] = true, -- Metamorphosis
    [145629] = true, -- Anti-Magic Zone
    [49039] = true, -- Lichborne
    [81256] = true, -- Dancing Rune Weapon
    [5487] = true, -- Bear Form
    [1966] = true, -- Feint
    [586] = true -- Fade
}

-- Auras nobody wants cluttering their raid frames.
local RAID_DEBUFF_EXCLUDE = {
    [57723] = true, -- Exhaustion (Heroism)
    [57724] = true, -- Sated (Bloodlust)
    [80354] = true, -- Temporal Displacement (Time Warp)
    [95809] = true, -- Insanity (Hunter pet Ancient Hysteria)
    [264689] = true, -- Fatigued (Drums of Fury / Primal Rage)
    [390435] = true, -- Exhaustion (Evoker Fury of the Aspects)
    [26013] = true, -- Deserter
    [71041] = true, -- Deserter
    [405692] = true -- Deserter
}

-- Important buffs & defensives get their own containers, so keep them out
-- of the plain "Buffs" row too.
local RAID_CURATED_EXCLUDE = {}
for id in pairs(IMPORTANT_BUFFS) do RAID_CURATED_EXCLUDE[id] = true end
for id in pairs(RAID_DEFENSIVES) do RAID_CURATED_EXCLUDE[id] = true end

local BLIZZARD_RAID_AURA_CVARS = {"raidFramesDisplayBuffs", "raidFramesDisplayDebuffs", "raidFramesCenterBigDefensive"}

local function RaidFilter(...)
    return AuraUtil.CreateFilterString(...)
end

----------------------------------------------------------------------
-- Colors (kept in sync with the palette in _main.lua)
----------------------------------------------------------------------
local COLOR_BUFF_BORDER = {0, 0, 0, 1}             -- solid black - "nothing special"
local COLOR_OTHER_BORDER = {0, 0, 0, 1}             -- solid black, same as buffs/debuffs

-- The rounded-square mask used on every aura icon + its border backing.
local ICON_MASK = "Interface\\AddOns\\" .. addonName .. "\\Media\\Textures\\AuraMask.png"

-- Debuff borders are colored by dispel type (Magic/Curse/Disease/Poison/
-- Bleed) using the client's own dispel-type colors and its declarative
-- aura-border curve API.
local DispelColorCurve = C_CurveUtil.CreateColorCurve()
DispelColorCurve:SetType(Enum.LuaCurveType.Step)
DispelColorCurve:AddPoint(0, DEBUFF_TYPE_NONE_COLOR)
DispelColorCurve:AddPoint(1, DEBUFF_TYPE_MAGIC_COLOR)
DispelColorCurve:AddPoint(2, DEBUFF_TYPE_CURSE_COLOR)
DispelColorCurve:AddPoint(3, DEBUFF_TYPE_DISEASE_COLOR)
DispelColorCurve:AddPoint(4, DEBUFF_TYPE_POISON_COLOR)
DispelColorCurve:AddPoint(9, DEBUFF_TYPE_BLEED_COLOR)
DispelColorCurve:AddPoint(11, DEBUFF_TYPE_BLEED_COLOR)

----------------------------------------------------------------------
-- Aura button construction
----------------------------------------------------------------------
local JuiRaidAuraFrames = {}   -- [CompactUnitFrame] = true
local JuiRaidAuraButtons = {}  -- [auraButton] = { baseDuration, baseCount, category }

local function GetTextScale()
    local durScale = (db.durationTextSize or 100) / 100
    local cntScale = (db.countTextSize or 100) / 100
    return durScale, cntScale
end

-- "Show numbers" / "Centre stacks" are per-row (buffs vs debuffs), matching
-- how mini-auras splits them.
local function GetNumbersEnabled(category)
    if category == "debuff" then
        return db.debuffNumbers ~= false
    end
    return db.buffNumbers ~= false
end

local function GetCenterStacks(category)
    if category == "debuff" then
        return db.debuffCenterStacks == true
    end
    return db.buffCenterStacks == true
end

-- Applies the numbers / centre-stacks choice to one button. With centre
-- stacks on, the stack count takes the middle of the icon and the countdown
-- text is hidden, so the two never fight for the same spot.
local function ApplyAuraTextDisplay(auraFrame)
    local info = JuiRaidAuraButtons[auraFrame]
    if not info then return end

    local centerStacks = GetCenterStacks(info.category)
    local showNumbers = GetNumbersEnabled(info.category)

    if auraFrame.Count then
        auraFrame.Count:ClearAllPoints()
        if centerStacks then
            auraFrame.Count:SetPoint("CENTER", auraFrame.Icon, "CENTER", 0, 0)
        else
            auraFrame.Count:SetPoint("TOPRIGHT", auraFrame.Icon, "TOPRIGHT", 1, -1)
        end
    end

    if auraFrame.CooldownText then
        auraFrame.CooldownText:SetShown(showNumbers and not centerStacks)
    end
end

-- category: "buff" | "debuff" | "other"
-- Both the icon and its border backing are cut to a rounded-square using
-- the same alpha mask, so the border reads as a clean rounded outline
-- rather than a square frame around a round icon.
local function CreateAuraButton(auraFrame, category, size)
    auraFrame:SetSize(size, size)

    if auraFrame.juiInit then
        return
    end
    auraFrame.juiInit = true

    local inset = 2 -- border thickness in px, visible around the rounded icon

    -- Border backing: a flat colored rounded-square that peeks out from
    -- behind the (smaller) rounded icon.
    auraFrame.Border = auraFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    auraFrame.Border:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", -inset, inset)
    auraFrame.Border:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", inset, -inset)
    auraFrame.Border:SetColorTexture(1, 1, 1, 1)

    auraFrame.BorderMask = auraFrame:CreateMaskTexture()
    auraFrame.BorderMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    auraFrame.BorderMask:SetAllPoints(auraFrame.Border)
    auraFrame.Border:AddMaskTexture(auraFrame.BorderMask)

    -- Debuffs get a second border layered on top, tinted by dispel type.
    -- Keeping them separate means turning dispel colours off still leaves a
    -- normal black border rather than no border at all.
    if category == "debuff" then
        auraFrame.DispelBorder = auraFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        auraFrame.DispelBorder:SetAllPoints(auraFrame.Border)
        auraFrame.DispelBorder:SetColorTexture(1, 1, 1, 1)
        auraFrame.DispelBorder:AddMaskTexture(auraFrame.BorderMask)

        auraFrame:SetAuraBorder(auraFrame.DispelBorder, {
            showIcon = false,
            showWhenHarmful = true,
            showWhenHelpful = false,
            showWithoutDispelType = true,
            customDispelColorCurve = DispelColorCurve,
            style = AuraButtonBorderStyle.Color
        })
        auraFrame.DispelBorder:SetAlpha(db.dispelColors ~= false and 1 or 0)
    end

    -- Icon, rounded to match the border.
    auraFrame.Icon = auraFrame:CreateTexture(nil, "ARTWORK")
    auraFrame.Icon:SetAllPoints(auraFrame)
    auraFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    auraFrame:SetIcon(auraFrame.Icon)

    auraFrame.IconMask = auraFrame:CreateMaskTexture()
    auraFrame.IconMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    auraFrame.IconMask:SetAllPoints(auraFrame.Icon)
    auraFrame.Icon:AddMaskTexture(auraFrame.IconMask)

    -- Cooldown swipe + Blizzard's own countdown number (restyled below)
    auraFrame.Cooldown = CreateFrame("Cooldown", nil, auraFrame, "CooldownFrameTemplate")
    auraFrame.Cooldown:SetAllPoints(auraFrame.Icon)
    auraFrame.Cooldown:SetReverse(true)
    auraFrame.Cooldown:SetDrawBling(false)
    auraFrame.Cooldown:SetCountdownFont("NumberFontNormalSmall")
    auraFrame:SetDurationCooldown(auraFrame.Cooldown)

    local durScale, cntScale = GetTextScale()
    local baseDuration = math.max(math.floor(size / 3 + 2), 6)
    local baseCount = math.max(math.floor(size / 3), 6)
    local durationFontSize = math.max(math.floor(baseDuration * durScale), 6)
    local countFontSize = math.max(math.floor(baseCount * cntScale), 6)

    -- Stack count
    auraFrame.Count = auraFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    Jui.Fonts:Apply(auraFrame.Count, countFontSize)
    auraFrame.Count:SetPoint("TOPRIGHT", auraFrame.Icon, "TOPRIGHT", 1, -1)
    auraFrame:SetApplicationCount(auraFrame.Count)

    -- Duration text: this is Blizzard's OWN built-in Cooldown countdown
    -- text (obtained via the native GetCountdownFontString API), not a
    -- FontString this addon created - it lives inside the secure/
    -- protected CompactUnitFrame hierarchy, since aura buttons are built
    -- via hooksecurefunc("CompactUnitFrame_SetUnit", ...). Once that
    -- hierarchy is tainted, SetFont on it can throw "forbidden object"
    -- errors - wrapped in pcall so that failure is silent (falls back to
    -- Blizzard's own default size/font for the countdown) rather than an
    -- uncaught error, and so it doesn't abort the rest of this function.
    auraFrame.CooldownText = auraFrame.Cooldown:GetCountdownFontString()
    pcall(Jui.Fonts.Apply, Jui.Fonts, auraFrame.CooldownText, durationFontSize)
    auraFrame.CooldownText:ClearAllPoints()
    auraFrame.CooldownText:SetPoint("CENTER", auraFrame.Icon, "CENTER", 0, 0)

    JuiRaidAuraButtons[auraFrame] = {
        baseDuration = baseDuration,
        baseCount = baseCount,
        category = category
    }

    -- Border color: neutral for plain buffs and debuffs (the dispel ring sits
    -- on top for debuffs), accent for "Other" (important defensives).
    if category == "other" then
        auraFrame.Border:SetVertexColor(unpack(COLOR_OTHER_BORDER))
    else
        auraFrame.Border:SetVertexColor(unpack(COLOR_BUFF_BORDER))
    end

    ApplyAuraTextDisplay(auraFrame)

    auraFrame:SetMouseMotionEnabled(db.tooltips ~= false)
end

----------------------------------------------------------------------
-- Filter strings (rebuilt whenever a filter toggle changes)
----------------------------------------------------------------------
-- "Mine" restricts the buff row to auras you cast yourself.
local function GetBuffFilterString()
    if db.buffsMine ~= false then
        return RaidFilter("HELPFUL", "PLAYER", "RAID_IN_COMBAT", "!BIG_DEFENSIVE", "!EXTERNAL_DEFENSIVE")
    end
    return RaidFilter("HELPFUL", "RAID_IN_COMBAT", "!BIG_DEFENSIVE", "!EXTERNAL_DEFENSIVE")
end

-- "Dispellable only" restricts the debuff row to what your spec can cleanse.
local function GetDebuffFilterString()
    if db.debuffsDispellable == true then
        return RaidFilter("HARMFUL", "DISPELLABLE")
    end
    return RaidFilter("HARMFUL")
end

local function GetMaxBuffIcons()
    return db.maxBuffs or RAID_MAX_BUFFS
end

local function GetMaxDebuffIcons()
    return db.maxDebuffs or 5
end

----------------------------------------------------------------------
-- Per-frame container setup
----------------------------------------------------------------------
local function GetSizes()
    local buffSize = db.buffSize or 28
    local debuffSize = db.debuffSize or 32
    local bigDebuffSize = math.floor(debuffSize * (db.dispelScale or 1.3) + 0.5)
    return buffSize, debuffSize, bigDebuffSize
end

local function GetOtherSize()
    return db.otherSize or OTHER_BASE_SIZE
end

local function EnsureContainers(frame)
    if frame.juiAuraData then
        return frame.juiAuraData
    end

    local data = {}
    local buffSize, debuffSize, bigDebuffSize = GetSizes()

    local buffAnchor = CreateFrame("Frame", nil, frame)
    buffAnchor:SetSize(1, 1)
    data.buffAnchor = buffAnchor

    local debuffAnchor = CreateFrame("Frame", nil, frame)
    debuffAnchor:SetSize(1, 1)
    data.debuffAnchor = debuffAnchor

    -- Buffs
    local buffContainer = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    buffContainer.juiSizes = {Buffs = buffSize, BuffsImportant = buffSize}
    buffContainer:SetFlowLayoutAnchorPoint("BOTTOMRIGHT")
    buffContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Up)
    data.buffsFilters = {excludeSpellIDs = RAID_CURATED_EXCLUDE, isFriendly = true}
    buffContainer:AddAuraGroup("Buffs", GetBuffFilterString(), {
        maxFrameCount = GetMaxBuffIcons(),
        candidateFilters = data.buffsFilters,
        initializeFrame = function(auraFrame) CreateAuraButton(auraFrame, "buff", buffContainer.juiSizes.Buffs) end,
        layout = {elementSpacing = RAID_ICON_GAP, lineSpacing = RAID_ICON_GAP}
    })
    buffContainer:AddAuraGroup("BuffsImportant", RaidFilter("HELPFUL", "PLAYER"), {
        maxFrameCount = (db.showImportantBuffs ~= false) and GetMaxBuffIcons() or 0,
        candidateFilters = {includeSpellIDs = IMPORTANT_BUFFS, isFriendly = true},
        initializeFrame = function(auraFrame) CreateAuraButton(auraFrame, "buff", buffContainer.juiSizes.BuffsImportant) end,
        layout = {elementSpacing = RAID_ICON_GAP, lineSpacing = RAID_ICON_GAP}
    })
    buffContainer:SetEnabled(false)
    data.buffContainer = buffContainer

    -- Debuffs
    local debuffContainer = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    debuffContainer:SetFrameLevel(buffContainer:GetFrameLevel() + 10)
    debuffContainer.juiSizes = {DebuffsBig = bigDebuffSize, DebuffsNormal = debuffSize}
    debuffContainer:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
    debuffContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
    -- Boss/role debuffs get the enlarged slot; everything else is "normal".
    data.debuffsBigFilters = {isBossOrRoleAura = true, excludeSpellIDs = RAID_DEBUFF_EXCLUDE, isFriendly = true}
    debuffContainer:AddAuraGroup("DebuffsBig", GetDebuffFilterString(), {
        maxFrameCount = RAID_MAX_BIG_DEBUFFS,
        candidateFilters = data.debuffsBigFilters,
        initializeFrame = function(auraFrame) CreateAuraButton(auraFrame, "debuff", debuffContainer.juiSizes.DebuffsBig) end,
        layout = {elementSpacing = RAID_ICON_GAP, lineSpacing = RAID_ICON_GAP}
    })
    data.debuffsNormalFilters = {isBossOrRoleAura = false, excludeSpellIDs = RAID_DEBUFF_EXCLUDE, isFriendly = true}
    debuffContainer:AddAuraGroup("DebuffsNormal", GetDebuffFilterString(), {
        maxFrameCount = GetMaxDebuffIcons(),
        candidateFilters = data.debuffsNormalFilters,
        initializeFrame = function(auraFrame) CreateAuraButton(auraFrame, "debuff", debuffContainer.juiSizes.DebuffsNormal) end,
        layout = {elementSpacing = RAID_ICON_GAP, lineSpacing = RAID_ICON_GAP}
    })
    debuffContainer:SetEnabled(false)
    data.debuffContainer = debuffContainer

    -- "Other" (important personal/party defensives) - created at the fixed
    -- OTHER_BASE_SIZE (see its definition above for why), not the
    -- frame-height-derived otherSize computed further up.
    local otherContainer = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    local healthLevel = (frame.healthBar and frame.healthBar:GetFrameLevel()) or frame:GetFrameLevel()
    otherContainer:SetFrameLevel(math.max(healthLevel, frame:GetFrameLevel()) + 10)
    otherContainer.juiSizes = {BigDefensives = OTHER_BASE_SIZE, AdditionalDefensives = OTHER_BASE_SIZE}
    otherContainer:AddAuraGroup("BigDefensives", RaidFilter("HELPFUL", "BIG_DEFENSIVE"), {
        maxFrameCount = RAID_MAX_DEFENSIVE,
        candidateFilters = {excludeSpellIDs = RAID_CURATED_EXCLUDE, isFriendly = true},
        initializeFrame = function(auraFrame) CreateAuraButton(auraFrame, "other", OTHER_BASE_SIZE) end,
        layout = {elementSpacing = RAID_ICON_GAP, lineSpacing = RAID_ICON_GAP}
    })
    data.additionalDefensivesFilters = {includeSpellIDs = RAID_DEFENSIVES, isFriendly = true}
    otherContainer:AddAuraGroup("AdditionalDefensives", RaidFilter("HELPFUL"), {
        maxFrameCount = RAID_MAX_DEFENSIVE,
        candidateFilters = data.additionalDefensivesFilters,
        initializeFrame = function(auraFrame) CreateAuraButton(auraFrame, "other", OTHER_BASE_SIZE) end,
        layout = {elementSpacing = RAID_ICON_GAP, lineSpacing = RAID_ICON_GAP}
    })
    otherContainer:SetEnabled(false)
    data.otherContainer = otherContainer

    frame.juiAuraData = data
    JuiRaidAuraFrames[frame] = true

    return data
end

local function PositionAnchors(frame, data)
    local powerBar = frame.powerBar
    local hasPower = powerBar and powerBar:IsShown()
    local refFrame = hasPower and powerBar or frame
    local rightRef = hasPower and "TOPRIGHT" or "BOTTOMRIGHT"
    local leftRef = hasPower and "TOPLEFT" or "BOTTOMLEFT"
    local yOffset = hasPower and 1 or 2

    data.buffAnchor:ClearAllPoints()
    data.buffAnchor:SetPoint("BOTTOMRIGHT", refFrame, rightRef, -2, yOffset)

    data.debuffAnchor:ClearAllPoints()
    data.debuffAnchor:SetPoint("BOTTOMLEFT", refFrame, leftRef, 2, yOffset)
end

-- Swaps which bottom corner buffs/debuffs grow from.
local function ApplyAuraSides(data)
    local buffContainer, debuffContainer = data.buffContainer, data.debuffContainer
    if not buffContainer or not debuffContainer then return end

    local debuffsRight = (db.debuffSide == "RIGHT")
    local debuffAnchor = debuffsRight and data.buffAnchor or data.debuffAnchor
    local buffAnchor = debuffsRight and data.debuffAnchor or data.buffAnchor
    local debuffPoint = debuffsRight and "BOTTOMRIGHT" or "BOTTOMLEFT"
    local buffPoint = debuffsRight and "BOTTOMLEFT" or "BOTTOMRIGHT"
    local debuffGrowth = debuffsRight and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right
    local buffGrowth = debuffsRight and AnchorUtil.FlowDirection.Right or AnchorUtil.FlowDirection.Left

    debuffContainer:ClearAllPoints()
    debuffContainer:SetPoint(debuffPoint, debuffAnchor, debuffPoint, 0, 0)
    debuffContainer:SetFlowLayoutAnchorPoint(debuffPoint)
    debuffContainer:SetFlowLayoutGrowthDirection(debuffGrowth, AnchorUtil.FlowDirection.Up)

    buffContainer:ClearAllPoints()
    buffContainer:SetPoint(buffPoint, buffAnchor, buffPoint, 0, 0)
    buffContainer:SetFlowLayoutAnchorPoint(buffPoint)
    buffContainer:SetFlowLayoutGrowthDirection(buffGrowth, AnchorUtil.FlowDirection.Up)
end

local function ApplyOtherPosition(frame, otherContainer)
    local point = db.otherPoint or "CENTER"
    local x = db.otherX or 0
    local y = db.otherY or 0

    otherContainer:ClearAllPoints()
    if point == "RIGHT" then
        otherContainer:SetFlowLayoutAnchorPoint("RIGHT")
        otherContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down)
        otherContainer:SetPoint("RIGHT", frame, "RIGHT", x, y)
    elseif point == "LEFT" then
        otherContainer:SetFlowLayoutAnchorPoint("LEFT")
        otherContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        otherContainer:SetPoint("LEFT", frame, "LEFT", x, y)
    else
        otherContainer:SetFlowLayoutAnchorPoint("LEFT")
        otherContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        otherContainer:SetPoint("CENTER", frame, "CENTER", x, y)
    end
end

-- Re-applies the PvP-only maxDuration cap to the groups that carry
-- permanent/no-timer auras.
local SHORT_AURA_DURATION = 60

-- Combines the PvP-only permanent-aura cap with the user's "Under 1 min"
-- toggles - whichever is tighter wins, so enabling Short only inside an
-- arena doesn't accidentally loosen the PvP cap.
local function EffectiveMaxDuration(pvpCap, shortOnly)
    if shortOnly then
        return pvpCap and math.min(pvpCap, SHORT_AURA_DURATION) or SHORT_AURA_DURATION
    end
    return pvpCap
end

local function ApplyDurationFilters(data)
    if not data.buffContainer then return end

    local pvp = IsPvpInstance()
    local buffShort = db.buffsShortOnly == true
    local debuffShort = db.debuffsShortOnly == true

    local maxDur = EffectiveMaxDuration(pvp and RAID_BUFF_MAX_DURATION or nil, buffShort)
    local maxDebuffDur = EffectiveMaxDuration(pvp and RAID_DEBUFF_MAX_DURATION or nil, debuffShort)
    -- Defensives follow the buff row's PvP cap but never the Short only
    -- toggle - a defensive worth showing is usually longer than a minute.
    local maxDefDur = pvp and RAID_BUFF_MAX_DURATION or nil

    if data.buffsFilters.maxDuration ~= maxDur then
        data.buffsFilters.maxDuration = maxDur
        data.buffContainer:SetAuraGroupCandidateFilters("Buffs", data.buffsFilters)
    end
    if data.debuffsBigFilters.maxDuration ~= maxDebuffDur then
        data.debuffsBigFilters.maxDuration = maxDebuffDur
        data.debuffContainer:SetAuraGroupCandidateFilters("DebuffsBig", data.debuffsBigFilters)
    end
    if data.debuffsNormalFilters.maxDuration ~= maxDebuffDur then
        data.debuffsNormalFilters.maxDuration = maxDebuffDur
        data.debuffContainer:SetAuraGroupCandidateFilters("DebuffsNormal", data.debuffsNormalFilters)
    end
    if data.additionalDefensivesFilters.maxDuration ~= maxDefDur then
        data.additionalDefensivesFilters.maxDuration = maxDefDur
        data.otherContainer:SetAuraGroupCandidateFilters("AdditionalDefensives", data.additionalDefensivesFilters)
    end
end

----------------------------------------------------------------------
-- Refresh loop
----------------------------------------------------------------------
local function RefreshFrame(frame)
    if not frame or frame:IsForbidden() or not frame.unit then return end

    local name = frame:GetName()
    if not name or not (name:match("^CompactParty") or name:match("^CompactRaid")) then return end

    local data = EnsureContainers(frame)
    PositionAnchors(frame, data)

    local unit = frame.displayedUnit or frame.unit
    if not unit or unit:match("target") then return end

    -- Truly unreachable (disconnected/phased/not visible): hide everything.
    local unreachable = (UnitPhaseReason and UnitPhaseReason(unit) ~= nil) or (UnitIsVisible and not UnitIsVisible(unit))
    local notAssistable = UnitCanAssist and not UnitCanAssist("player", unit)

    ApplyDurationFilters(data)

    local buffContainer, debuffContainer, otherContainer = data.buffContainer, data.debuffContainer, data.otherContainer
    local buffS = buffContainer.juiSizes.Buffs
    local bigS = debuffContainer.juiSizes.DebuffsBig
    local normalS = debuffContainer.juiSizes.DebuffsNormal
    local otherS = otherContainer.juiSizes.BigDefensives
    local buffsPerRow = db.buffsPerRow or RAID_BUFFS_PER_ROW
    local debuffsPerRow = db.debuffsPerRow or 5

    buffContainer:SetFlowLayoutMaximumLineSize(buffsPerRow * (buffS + RAID_ICON_GAP))
    -- The big (boss/role) debuffs share the row with the normal ones, so the
    -- line has to be wide enough for both before it wraps.
    debuffContainer:SetFlowLayoutMaximumLineSize(RAID_MAX_BIG_DEBUFFS * (bigS + RAID_ICON_GAP) + debuffsPerRow * (normalS + RAID_ICON_GAP))
    otherContainer:SetFlowLayoutMaximumLineSize(RAID_MAX_DEFENSIVE * (otherS + RAID_ICON_GAP))

    ApplyAuraSides(data)
    ApplyOtherPosition(frame, otherContainer)

    if unreachable then
        for _, container in ipairs({buffContainer, debuffContainer, otherContainer}) do
            if container.juiUnit ~= nil then
                container:SetEnabled(false)
                container.juiUnit = nil
                container:Hide()
            end
        end
        return
    end

    if notAssistable then
        if otherContainer.juiUnit ~= nil then
            otherContainer:SetEnabled(false)
            otherContainer.juiUnit = nil
            otherContainer:Hide()
        end
    else
        if otherContainer.juiUnit ~= unit then
            otherContainer:SetUnit(unit)
            otherContainer:SetEnabled(true)
            otherContainer.juiUnit = unit
            otherContainer:Show()
        end
        otherContainer:UpdateAllAuras()
    end

    for _, container in ipairs({buffContainer, debuffContainer}) do
        if container.juiUnit ~= unit then
            container:SetUnit(unit)
            container:SetEnabled(true)
            container.juiUnit = unit
            container:Show()
        end
        container:UpdateAllAuras()
    end
end

----------------------------------------------------------------------
-- Enable / disable
----------------------------------------------------------------------
local function SetBlizzardRaidAurasEnabled(enabled)
    local value = enabled and "1" or "0"
    for _, cvar in ipairs(BLIZZARD_RAID_AURA_CVARS) do
        pcall(SetCVar, cvar, value)
    end
end

local hooked = false
local ticker

local function EnableRaidAuras()
    if hooked then return end
    hooked = true

    SetBlizzardRaidAurasEnabled(false)
    hooksecurefunc("CompactUnitFrame_SetUnit", RefreshFrame)

    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(1, function()
        for frame in pairs(JuiRaidAuraFrames) do
            RefreshFrame(frame)
        end
    end)
end

----------------------------------------------------------------------
-- Live-update helpers (for sliders/dropdowns that don't need a reload)
----------------------------------------------------------------------
local function UpdateAllSizes()
    local buffSize, debuffSize, bigDebuffSize = GetSizes()
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.buffContainer and not frame:IsForbidden() then
            local otherSize = GetOtherSize()

            local base = data.buffContainer.juiSizes.Buffs
            if base and base > 0 then data.buffContainer:SetScale(buffSize / base) end

            base = data.debuffContainer.juiSizes.DebuffsNormal
            if base and base > 0 then data.debuffContainer:SetScale(debuffSize / base) end

            -- base is now always OTHER_BASE_SIZE (36) - the fixed size
            -- these icons are actually created at (see EnsureContainers
            -- above) - rather than a frame-height-derived value that used
            -- to vary per-frame and make this ratio inconsistent.
            base = data.otherContainer.juiSizes.BigDefensives
            if base and base > 0 then data.otherContainer:SetScale(otherSize / base) end
        end
    end

    if RaidTest.isTesting then UpdateTestPreview() end
end

local function UpdateAllDebuffLimit()
    local maxDebuffs = GetMaxDebuffIcons()
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.debuffContainer and not frame:IsForbidden() then
            data.debuffContainer:SetAuraGroupMaxFrameCount("DebuffsNormal", maxDebuffs)
        end
    end
end

-- Max buff icons, and whether the "important buffs" group is drawn at all.
local function UpdateAllBuffLimit()
    local maxBuffs = GetMaxBuffIcons()
    local importantCount = (db.showImportantBuffs ~= false) and maxBuffs or 0
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.buffContainer and not frame:IsForbidden() then
            data.buffContainer:SetAuraGroupMaxFrameCount("Buffs", maxBuffs)
            data.buffContainer:SetAuraGroupMaxFrameCount("BuffsImportant", importantCount)
        end
    end
end

-- "Mine" / "Dispellable only" swap the group's filter string in place.
local function UpdateAllFilterStrings()
    local buffFilter = GetBuffFilterString()
    local debuffFilter = GetDebuffFilterString()
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.buffContainer and not frame:IsForbidden() then
            data.buffContainer:SetAuraGroupFilterString("Buffs", buffFilter)
            data.debuffContainer:SetAuraGroupFilterString("DebuffsBig", debuffFilter)
            data.debuffContainer:SetAuraGroupFilterString("DebuffsNormal", debuffFilter)
        end
    end
end

-- "Under 1 min" - re-run the duration filters on every tracked frame.
local function UpdateAllDurationFilters()
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.buffContainer and not frame:IsForbidden() then
            ApplyDurationFilters(data)
        end
    end
end

-- "Show numbers" / "Centre stacks"
local function UpdateAllTextDisplay()
    for auraFrame in pairs(JuiRaidAuraButtons) do
        ApplyAuraTextDisplay(auraFrame)
    end
end

-- "Dispel colours" - fade the dispel-tinted ring in/out, leaving the black
-- base border behind it.
local function UpdateAllDispelColors()
    local alpha = (db.dispelColors ~= false) and 1 or 0
    for auraFrame, info in pairs(JuiRaidAuraButtons) do
        if info.category == "debuff" and auraFrame.DispelBorder then
            pcall(auraFrame.DispelBorder.SetAlpha, auraFrame.DispelBorder, alpha)
        end
    end
    if RaidTest.isTesting then UpdateTestPreview() end
end

-- "Show defensives" - the Other/defensive row can be switched off entirely.
local function UpdateAllDefensiveVisibility()
    local show = db.showDefensives ~= false
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.otherContainer and not frame:IsForbidden() then
            data.otherContainer:SetAuraGroupMaxFrameCount("BigDefensives", show and RAID_MAX_DEFENSIVE or 0)
            data.otherContainer:SetAuraGroupMaxFrameCount("AdditionalDefensives", show and RAID_MAX_DEFENSIVE or 0)
        end
    end
end

local function UpdateAllSides()
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.buffContainer and not frame:IsForbidden() then
            ApplyAuraSides(data)
        end
    end
end

local function UpdateAllOtherPosition()
    for frame in pairs(JuiRaidAuraFrames) do
        local data = frame.juiAuraData
        if data and data.otherContainer and not frame:IsForbidden() then
            ApplyOtherPosition(frame, data.otherContainer)
            data.otherContainer:UpdateAllAuras()
        end
    end
end

local function UpdateAllTextSizes()
    local durScale, cntScale = GetTextScale()
    for auraFrame, sizes in pairs(JuiRaidAuraButtons) do
        local durSize = math.max(math.floor(sizes.baseDuration * durScale), 6)
        local cntSize = math.max(math.floor(sizes.baseCount * cntScale), 6)
        -- CooldownText is Blizzard's own protected countdown FontString
        -- (see the comment where it's first assigned above) - pcall'd for
        -- the same taint reason. Count is a plain FontString this addon
        -- created itself, not part of the protected hierarchy, so it
        -- doesn't need the same guard.
        pcall(Jui.Fonts.Apply, Jui.Fonts, auraFrame.CooldownText, durSize)
        Jui.Fonts:Apply(auraFrame.Count, cntSize)
    end
end

local function UpdateAllTooltips()
    local enabled = db.tooltips ~= false
    for auraFrame in pairs(JuiRaidAuraButtons) do
        pcall(auraFrame.SetMouseMotionEnabled, auraFrame, enabled)
    end
end

-- Per-row / layout changes need a full re-flow rather than a single setter.
local function UpdateAllLayout()
    for frame in pairs(JuiRaidAuraFrames) do
        if not frame:IsForbidden() then
            RefreshFrame(frame)
        end
    end
end

----------------------------------------------------------------------
-- Test preview - standalone icons (not real AuraButton widgets, which
-- only exist inside a real AuraContainer) that mimic the same rounded-
-- icon + border look via the same mask texture, so buff/debuff/other
-- sizing and the dispel-color toggle can be previewed without being in
-- a group.
----------------------------------------------------------------------
RaidTest = {isTesting = false, icons = {}}

local function CreateTestIcon(parent, dispelColor)
    local f = CreateFrame("Frame", nil, parent)

    f.Border = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.Border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.Border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.Border:SetColorTexture(0, 0, 0, 1)
    local borderMask = f:CreateMaskTexture()
    borderMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    borderMask:SetAllPoints(f.Border)
    f.Border:AddMaskTexture(borderMask)

    if dispelColor then
        f.DispelBorder = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.DispelBorder:SetAllPoints(f.Border)
        f.DispelBorder:SetColorTexture(dispelColor[1], dispelColor[2], dispelColor[3], 1)
        f.DispelBorder:AddMaskTexture(borderMask)
    end

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints()
    f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.Icon:SetTexture("Interface\\Icons\\Spell_Holy_PowerWordShield")
    local iconMask = f:CreateMaskTexture()
    iconMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    iconMask:SetAllPoints(f.Icon)
    f.Icon:AddMaskTexture(iconMask)

    return f
end

local testFrame = CreateFrame("Frame", nil, UIParent)
testFrame:SetSize(10, 10)
testFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
testFrame:SetFrameStrata("HIGH")
testFrame:Hide()

RaidTest.icons.buff1 = CreateTestIcon(testFrame)
RaidTest.icons.buff2 = CreateTestIcon(testFrame)
RaidTest.icons.buff3 = CreateTestIcon(testFrame)
RaidTest.icons.debuff1 = CreateTestIcon(testFrame, {0.2, 0.6, 1})   -- Magic-style blue
RaidTest.icons.debuff2 = CreateTestIcon(testFrame, {0.2, 0.8, 0.2}) -- Poison-style green
RaidTest.icons.debuffBig = CreateTestIcon(testFrame, {0.8, 0.2, 0.2}) -- Curse-style red
RaidTest.icons.other = CreateTestIcon(testFrame)

UpdateTestPreview = function()
    local buffSize, debuffSize, bigDebuffSize = GetSizes()
    local otherSize = GetOtherSize()
    local gap = 4

    for _, icon in pairs({RaidTest.icons.debuff1, RaidTest.icons.debuff2, RaidTest.icons.debuffBig}) do
        if icon.DispelBorder then icon.DispelBorder:SetAlpha(db.dispelColors ~= false and 1 or 0) end
    end

    -- Buffs, left group
    local x = 0
    for _, key in ipairs({"buff1", "buff2", "buff3"}) do
        local icon = RaidTest.icons[key]
        icon:SetSize(buffSize, buffSize)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", testFrame, "LEFT", x, 0)
        x = x + buffSize + gap
    end

    -- Debuffs (two normal + one enlarged), right of the buffs with a gap
    x = x + 20
    for _, key in ipairs({"debuff1", "debuff2"}) do
        local icon = RaidTest.icons[key]
        icon:SetSize(debuffSize, debuffSize)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", testFrame, "LEFT", x, 0)
        x = x + debuffSize + gap
    end
    RaidTest.icons.debuffBig:SetSize(bigDebuffSize, bigDebuffSize)
    RaidTest.icons.debuffBig:ClearAllPoints()
    RaidTest.icons.debuffBig:SetPoint("LEFT", testFrame, "LEFT", x, 0)
    x = x + bigDebuffSize + 20

    -- "Other" (important defensive), further right
    RaidTest.icons.other:SetSize(otherSize, otherSize)
    RaidTest.icons.other:ClearAllPoints()
    RaidTest.icons.other:SetPoint("LEFT", testFrame, "LEFT", x, 0)
end

----------------------------------------------------------------------
-- Module registration
----------------------------------------------------------------------
local mod = Jui:RegisterModule({
    id = "raidAuras",
    name = "Raid Auras",
    description = "Custom buffs, debuffs and other on party & raid frames.",
    enabledByDefault = false,
    category = "auras",
})

function mod:OnEnable()
    db = Jui.Database:Get().raidAuras
    EnableRaidAuras()
end

-- The CompactUnitFrame_SetUnit hook is a permanent hooksecurefunc - it
-- can't actually be un-hooked. Disabling restores Blizzard's own CVars
-- (so the default raid aura display comes back) but the custom hook stays
-- installed until a reload, same honest trade-off the pre-1.0 addon had.
function mod:OnDisable()
    SetBlizzardRaidAurasEnabled(true)
end

function mod:CreateSettings(parent)
    local GROUP_WIDTH = 650
    local COL2, COL3 = 225, 435

    local reloadNote = Jui.UI:CreateText(parent, "Small", C.textFaint)
    reloadNote:SetPoint("TOPLEFT", 0, 0)
    reloadNote:SetText("Enabling/disabling this module fully takes effect after a UI reload.")

    local generalGroup = Jui.UI:CreateSection(parent, "General", nil, GROUP_WIDTH)
    generalGroup:SetPoint("TOPLEFT", reloadNote, "BOTTOMLEFT", 0, -10)
    generalGroup:SetSize(GROUP_WIDTH, 70)

    local tooltipCB = Jui.UI:CreateCheckbox(generalGroup, "Aura Tooltips",
        function() return db.tooltips end,
        function(v) db.tooltips = v; UpdateAllTooltips() end)
    tooltipCB:SetPoint("TOPLEFT", 15, generalGroup.ContentTop)

    local testBtn = Jui.UI:CreateButton(generalGroup, RaidTest.isTesting and "Stop Test" or "Test Display")
    testBtn:SetSize(120, 24)
    testBtn:SetPoint("TOPRIGHT", -15, generalGroup.ContentTop + 8)
    testBtn:SetScript("OnClick", function()
        if RaidTest.isTesting then
            RaidTest.isTesting = false
            testFrame:Hide()
            testBtn.Text:SetText("Test Display")
        else
            RaidTest.isTesting = true
            UpdateTestPreview()
            testFrame:Show()
            testBtn.Text:SetText("Stop Test")
        end
    end)

    ----------------------------------------------------------------------
    local buffGroup = Jui.UI:CreateSection(parent, "Buffs", nil, GROUP_WIDTH)
    buffGroup:SetPoint("TOPLEFT", generalGroup, "BOTTOMLEFT", 0, -18)
    buffGroup:SetSize(GROUP_WIDTH, 190)

    local buffMineCB = Jui.UI:CreateCheckbox(buffGroup, "Mine only",
        function() return db.buffsMine end,
        function(v) db.buffsMine = v; UpdateAllFilterStrings() end)
    buffMineCB:SetPoint("TOPLEFT", 15, buffGroup.ContentTop)

    local buffShortCB = Jui.UI:CreateCheckbox(buffGroup, "Under 1 min",
        function() return db.buffsShortOnly end,
        function(v) db.buffsShortOnly = v; UpdateAllDurationFilters() end)
    buffShortCB:SetPoint("TOPLEFT", COL2, buffGroup.ContentTop)

    local buffImportantCB = Jui.UI:CreateCheckbox(buffGroup, "Important",
        function() return db.showImportantBuffs end,
        function(v) db.showImportantBuffs = v; UpdateAllBuffLimit() end)
    buffImportantCB:SetPoint("TOPLEFT", COL3, buffGroup.ContentTop)

    local buffNumbersCB = Jui.UI:CreateCheckbox(buffGroup, "Show numbers",
        function() return db.buffNumbers end,
        function(v) db.buffNumbers = v; UpdateAllTextDisplay() end)
    buffNumbersCB:SetPoint("TOPLEFT", 15, buffGroup.ContentTop - 26)

    local buffStacksCB = Jui.UI:CreateCheckbox(buffGroup, "Centre stacks",
        function() return db.buffCenterStacks end,
        function(v) db.buffCenterStacks = v; UpdateAllTextDisplay() end)
    buffStacksCB:SetPoint("TOPLEFT", COL2, buffGroup.ContentTop - 26)

    local buffSizeSlider = Jui.UI:CreateSlider(buffGroup, "Buff Size", 10, 50,
        function() return db.buffSize end,
        function(v) db.buffSize = v; UpdateAllSizes() end)
    buffSizeSlider:SetPoint("TOPLEFT", 15, buffGroup.ContentTop - 75)

    local maxBuffsSlider = Jui.UI:CreateSlider(buffGroup, "Max Icons", 1, 9,
        function() return db.maxBuffs end,
        function(v) db.maxBuffs = v; UpdateAllBuffLimit() end)
    maxBuffsSlider:SetPoint("LEFT", buffSizeSlider, "RIGHT", 55, 0)

    local buffsPerRowSlider = Jui.UI:CreateSlider(buffGroup, "Icons Per Row", 1, 6,
        function() return db.buffsPerRow end,
        function(v) db.buffsPerRow = v; UpdateAllLayout() end)
    buffsPerRowSlider:SetPoint("LEFT", maxBuffsSlider, "RIGHT", 55, 0)

    ----------------------------------------------------------------------
    local debuffGroup = Jui.UI:CreateSection(parent, "Debuffs", nil, GROUP_WIDTH)
    debuffGroup:SetPoint("TOPLEFT", buffGroup, "BOTTOMLEFT", 0, -18)
    debuffGroup:SetSize(GROUP_WIDTH, 190)

    local debuffDispellableCB = Jui.UI:CreateCheckbox(debuffGroup, "Dispellable only",
        function() return db.debuffsDispellable end,
        function(v) db.debuffsDispellable = v; UpdateAllFilterStrings() end)
    debuffDispellableCB:SetPoint("TOPLEFT", 15, debuffGroup.ContentTop)

    local debuffShortCB = Jui.UI:CreateCheckbox(debuffGroup, "Under 1 min",
        function() return db.debuffsShortOnly end,
        function(v) db.debuffsShortOnly = v; UpdateAllDurationFilters() end)
    debuffShortCB:SetPoint("TOPLEFT", COL2, debuffGroup.ContentTop)

    local dispelColorCB = Jui.UI:CreateCheckbox(debuffGroup, "Dispel colours",
        function() return db.dispelColors end,
        function(v) db.dispelColors = v; UpdateAllDispelColors() end)
    dispelColorCB:SetPoint("TOPLEFT", COL3, debuffGroup.ContentTop)

    local debuffNumbersCB = Jui.UI:CreateCheckbox(debuffGroup, "Show numbers",
        function() return db.debuffNumbers end,
        function(v) db.debuffNumbers = v; UpdateAllTextDisplay() end)
    debuffNumbersCB:SetPoint("TOPLEFT", 15, debuffGroup.ContentTop - 26)

    local debuffStacksCB = Jui.UI:CreateCheckbox(debuffGroup, "Centre stacks",
        function() return db.debuffCenterStacks end,
        function(v) db.debuffCenterStacks = v; UpdateAllTextDisplay() end)
    debuffStacksCB:SetPoint("TOPLEFT", COL2, debuffGroup.ContentTop - 26)

    local debuffSizeSlider = Jui.UI:CreateSlider(debuffGroup, "Debuff Size", 10, 50,
        function() return db.debuffSize end,
        function(v) db.debuffSize = v; UpdateAllSizes() end)
    debuffSizeSlider:SetPoint("TOPLEFT", 15, debuffGroup.ContentTop - 75)

    local maxDebuffsSlider = Jui.UI:CreateSlider(debuffGroup, "Max Icons", 1, 9,
        function() return db.maxDebuffs end,
        function(v) db.maxDebuffs = v; UpdateAllDebuffLimit() end)
    maxDebuffsSlider:SetPoint("LEFT", debuffSizeSlider, "RIGHT", 55, 0)

    local debuffsPerRowSlider = Jui.UI:CreateSlider(debuffGroup, "Icons Per Row", 1, 6,
        function() return db.debuffsPerRow end,
        function(v) db.debuffsPerRow = v; UpdateAllLayout() end)
    debuffsPerRowSlider:SetPoint("LEFT", maxDebuffsSlider, "RIGHT", 55, 0)

    local dispelScaleSlider = Jui.UI:CreateSlider(debuffGroup, "Big Debuff Scale", 100, 200,
        function() return math.floor((db.dispelScale or 1.25) * 100 + 0.5) end,
        function(v) db.dispelScale = v / 100; UpdateAllSizes() end)
    dispelScaleSlider:SetPoint("TOPLEFT", debuffSizeSlider, "BOTTOMLEFT", 0, -45)

    local debuffSideDropdown = Jui.UI:CreateDropdown(debuffGroup, "Debuff Side",
        {{value = "LEFT", text = "Left"}, {value = "RIGHT", text = "Right"}},
        function() return db.debuffSide end,
        function(v) db.debuffSide = v; UpdateAllSides() end)
    debuffSideDropdown:SetPoint("LEFT", dispelScaleSlider, "RIGHT", 55, 6)

    ----------------------------------------------------------------------
    local otherGroup = Jui.UI:CreateSection(parent, "Other (Important Defensives)", nil, GROUP_WIDTH)
    otherGroup:SetPoint("TOPLEFT", debuffGroup, "BOTTOMLEFT", 0, -18)
    otherGroup:SetSize(GROUP_WIDTH, 160)

    local showDefensivesCB = Jui.UI:CreateCheckbox(otherGroup, "Show defensives",
        function() return db.showDefensives end,
        function(v) db.showDefensives = v; UpdateAllDefensiveVisibility() end)
    showDefensivesCB:SetPoint("TOPLEFT", 15, otherGroup.ContentTop)

    local otherSizeSlider = Jui.UI:CreateSlider(otherGroup, "Other Size", 20, 80,
        function() return db.otherSize end,
        function(v) db.otherSize = v; UpdateAllSizes() end)
    otherSizeSlider:SetPoint("TOPLEFT", 15, otherGroup.ContentTop - 52)

    local otherPointDropdown = Jui.UI:CreateDropdown(otherGroup, "Position",
        {{value = "CENTER", text = "Center"}, {value = "LEFT", text = "Left"}, {value = "RIGHT", text = "Right"}},
        function() return db.otherPoint end,
        function(v) db.otherPoint = v; UpdateAllOtherPosition() end)
    otherPointDropdown:SetPoint("LEFT", otherSizeSlider, "RIGHT", 55, 6)

    local otherXSlider = Jui.UI:CreateSlider(otherGroup, "X Offset", -100, 100,
        function() return db.otherX end,
        function(v) db.otherX = v; UpdateAllOtherPosition() end)
    otherXSlider:SetPoint("LEFT", otherPointDropdown, "RIGHT", 55, -6)

    local otherYSlider = Jui.UI:CreateSlider(otherGroup, "Y Offset", -100, 100,
        function() return db.otherY end,
        function(v) db.otherY = v; UpdateAllOtherPosition() end)
    otherYSlider:SetPoint("TOPLEFT", otherSizeSlider, "BOTTOMLEFT", 0, -45)

    ----------------------------------------------------------------------
    local textGroup = Jui.UI:CreateSection(parent, "Text", nil, GROUP_WIDTH)
    textGroup:SetPoint("TOPLEFT", otherGroup, "BOTTOMLEFT", 0, -18)
    textGroup:SetSize(GROUP_WIDTH, 90)

    local durTextSlider = Jui.UI:CreateSlider(textGroup, "Duration Text Size", 50, 200,
        function() return db.durationTextSize end,
        function(v) db.durationTextSize = v; UpdateAllTextSizes() end)
    durTextSlider:SetPoint("TOPLEFT", 15, textGroup.ContentTop)

    local cntTextSlider = Jui.UI:CreateSlider(textGroup, "Stack Count Text Size", 50, 200,
        function() return db.countTextSize end,
        function(v) db.countTextSize = v; UpdateAllTextSizes() end)
    cntTextSlider:SetPoint("LEFT", durTextSlider, "RIGHT", 55, 0)

    parent:SetHeight(830)
end

Jui.UI.Settings:RegisterModulePage("raidAuras", "Raid Auras", "auras")
