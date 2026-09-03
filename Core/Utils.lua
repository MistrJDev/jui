--[[
    Core/Utils.lua
    ---------------------------------------------------------------------
    Small, generic helpers that don't belong to any one module. Loaded
    first (after nothing) so everything else in the addon can rely on
    Jui.Utils existing.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.Utils = {}

-- True while actually inside a battleground (not an arena, not any other
-- kind of instance). This is the one check every battleground-facing
-- module cares about.
function Jui.Utils:IsInBattleground()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "pvp" then
        return false
    end

    -- Guarded: if this API is ever renamed/removed, fail toward "not a
    -- battleground" rather than erroring - the caller just won't show
    -- battleground-only UI, which is the safe direction to fail in.
    local ok, isArena = pcall(IsActiveBattlefieldArena)
    if ok and isArena then
        return false
    end

    return true
end

function Jui.Utils:GetCurrentMapID()
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then return mapID end
    return nil
end

function Jui.Utils:GetPlayerFaction()
    local faction = UnitFactionGroup("player")
    return faction or "Neutral"
end

function Jui.Utils:FormatTime(seconds)
    if not seconds or seconds < 0 then return "0:00" end
    seconds = math.floor(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

function Jui.Utils:Clamp(value, minV, maxV)
    if value < minV then return minV end
    if value > maxV then return maxV end
    return value
end

-- Deep-copies a plain table of settings (defaults tables, etc.) - values
-- only, no metatables, which is all Jui's saved data ever needs.
function Jui.Utils:CopyTable(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            out[k] = Jui.Utils:CopyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

-- Fills in any keys missing from `target` using `defaults`, recursively,
-- without overwriting anything the user already has set. This is the
-- backbone of the database migration in Core/Database.lua.
function Jui.Utils:ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            Jui.Utils:ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end
