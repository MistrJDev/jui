--[[
    Core/Modules.lua
    ---------------------------------------------------------------------
    Every feature (Capping, Queue Timer, Winrate, Loss of Control, Raid
    Auras, Player Auras) registers itself here instead of wiring itself
    directly into the UI. The UI only ever asks this registry "does this
    module exist / is it enabled / does it have settings" - it never needs
    to know how any individual module actually works.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.Modules = {}

local registry = {}   -- [id] = moduleDef
local order = {}      -- registration order, for stable UI listing

-- moduleDef = {
--     id, name, description, category ("gameplay"/"auras"/etc, optional),
--     enabledByDefault,
--     OnEnable = function(self) ... end,
--     OnDisable = function(self) ... end,
--     CreateSettings = function(self, parent) ... end, (optional)
-- }
function Jui:RegisterModule(def)
    assert(def.id, "RegisterModule: id is required")
    assert(not registry[def.id], "RegisterModule: '" .. def.id .. "' is already registered")

    def.state = "REGISTERED"

    -- Convenience wrapper so modules don't create their own event frames -
    -- every handler registered this way is tagged with the module's id,
    -- so Disable() below can cleanly unregister all of them at once.
    function def:RegisterEvent(event, fn)
        Jui.Events:Register(event, fn, self.id)
    end

    registry[def.id] = def
    table.insert(order, def.id)

    return def
end

function Jui.Modules:Get(id)
    return registry[id]
end

function Jui.Modules:GetAll()
    local list = {}
    for _, id in ipairs(order) do
        list[#list + 1] = registry[id]
    end
    return list
end

function Jui.Modules:IsEnabled(id)
    local db = Jui.Database:Get()
    if not db.modules or db.modules[id] == nil then
        local def = registry[id]
        return def and def.enabledByDefault or false
    end
    return db.modules[id] == true
end

function Jui.Modules:Enable(id)
    local def = registry[id]
    if not def then return end

    local db = Jui.Database:Get()
    db.modules[id] = true

    if def.state == "ACTIVE" then return end
    def.state = "INITIALIZE"
    if def.OnEnable then
        local ok, err = pcall(def.OnEnable, def)
        if not ok then
            geterrorhandler()(err)
            return
        end
    end
    def.state = "ACTIVE"
end

function Jui.Modules:Disable(id)
    local def = registry[id]
    if not def then return end

    local db = Jui.Database:Get()
    db.modules[id] = false

    if def.state ~= "ACTIVE" then return end
    if def.OnDisable then
        local ok, err = pcall(def.OnDisable, def)
        if not ok then geterrorhandler()(err) end
    end
    Jui.Events:UnregisterAllForOwner(id)
    def.state = "DISABLED"
end

-- Called once from Core/Init.lua, after the database is ready: brings
-- every registered module up to whatever state its saved setting says.
function Jui.Modules:InitializeAll()
    for _, id in ipairs(order) do
        if self:IsEnabled(id) then
            self:Enable(id)
        else
            registry[id].state = "DISABLED"
        end
    end
end
