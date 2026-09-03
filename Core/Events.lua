--[[
    Core/Events.lua
    ---------------------------------------------------------------------
    A single real event frame backs every registration in the addon.
    Modules register through Jui.Events (or the module:RegisterEvent
    convenience added in Core/Modules.lua) instead of each creating their
    own frame - and because every handler is tagged with the module that
    owns it, disabling a module can cleanly unregister everything it added
    without touching anything else.
--]]

local addonName, ns = ...

Jui = Jui or {}
Jui.Events = {}

local dispatcher = CreateFrame("Frame")
local handlers = {} -- [event] = { {fn = ..., owner = moduleId or nil}, ... }

dispatcher:SetScript("OnEvent", function(self, event, ...)
    local list = handlers[event]
    if not list then return end
    -- Iterate a shallow copy: a handler unregistering itself (or another
    -- handler for the same event) mid-dispatch shouldn't skip entries.
    for _, entry in ipairs({unpack(list)}) do
        local ok, err = pcall(entry.fn, event, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end)

function Jui.Events:Register(event, fn, owner)
    if not handlers[event] then
        handlers[event] = {}
        dispatcher:RegisterEvent(event)
    end
    table.insert(handlers[event], {fn = fn, owner = owner})
end

function Jui.Events:Unregister(event, fn)
    local list = handlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].fn == fn then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        dispatcher:UnregisterEvent(event)
        handlers[event] = nil
    end
end

-- Drops every handler tagged with this owner, across every event. Used
-- when a module is disabled.
function Jui.Events:UnregisterAllForOwner(owner)
    for event, list in pairs(handlers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            dispatcher:UnregisterEvent(event)
            handlers[event] = nil
        end
    end
end
