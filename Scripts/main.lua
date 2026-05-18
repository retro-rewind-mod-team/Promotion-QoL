-- ============================================================
--  Retro Rewind - Promotion-QoL
--  Version: 1.2
--
--  Automatically gives flyers to all walkby NPCs outside
--  the store, so you don't have to hand them out manually.
--
--  HOW IT WORKS:
--  When you open the store, the mod finds all walkby NPCs
--  and triggers the native flyer RNG for each one. New NPCs
--  that spawn while the store is open are queued and receive
--  their flyer after a short ingame delay.
--
--  The conversion chance is read directly from the AI Director
--  and reflects your store's popularity and decoration level.
--  A fully upgraded store has a higher chance than a new one.
--
--  USAGE:
--  Simply open your store via the Open/Closed sign. Flyers
--  are distributed automatically — no manual interaction needed.
-- ============================================================

local CONFIG = require("config")

-- ============================================================
-- INTERNAL
-- ============================================================
local P = "[Promotion-QoL] "

local function log(msg)
    print(P .. msg .. "\n")
end

local function debug(msg)
    if CONFIG.Debug then
        log(msg)
    end
end

local function safe(label, fn, ...)
    local results = {pcall(fn, ...)}
    if not results[1] then
        log(label .. " FAILED: " .. tostring(results[2]))
        return nil
    end
    return table.unpack(results, 2)
end

local registeredHooks = {}

local function registerHookOptional(path, callback)
    if registeredHooks[path] then return end
    registeredHooks[path] = true
    local ok, err = pcall(function() RegisterHook(path, callback) end)
    if ok then
        debug("Hook active: " .. path)
    else
        log("Hook error: " .. path .. " / " .. tostring(err))
    end
end

local clientCount   = 0
local flyerCount    = 0
local storeIsOpen   = false
local currentMinute = 0
local pendingNpcs   = {}
local realChance    = 0.25  -- fallback, updated from AI Director

-- ============================================================
-- HELPER: Reset per-day state
-- ============================================================
local function resetTrackers()
    storeIsOpen   = false
    clientCount   = 0
    flyerCount    = 0
    pendingNpcs   = {}
    currentMinute = 0
end

-- ============================================================
-- CORE: Update conversion chance from AI Director
-- ============================================================
local function updateChance()
    safe("updateChance", function()
        local directors = FindAllOf("AI_Director_C")
        if not directors or #directors == 0 then return end
        local result = {}
        directors[1]["Return Weight Chance of Spawning AI by Store Popularity and Deco"](result)
        if type(result["Weight"]) == "number" and result["Weight"] > 0 then
            realChance = result["Weight"]
            log("Conversion chance: " .. string.format("%.2f", realChance))
        end
    end)
end

-- ============================================================
-- CORE: Give flyer to a single NPC using native game chance
-- ============================================================
local function giveFlyerToNpc(npc)
    local chance = (CONFIG.conversionRate > 0) and (CONFIG.conversionRate / 100) or realChance
    if math.random() <= chance then
        npc["Walker Accept the flyer"]()
    else
        npc["Walker refuse the flyer"]()
    end
end

-- ============================================================
-- CORE: Give flyers to all current walkby NPCs
-- ============================================================
local function giveFlyersToAll()
    local npcs = FindAllOf("AI_WalkBy_Character_C")
    if not npcs or #npcs == 0 then
        log("No walkby NPCs found")
        return
    end
    log("Found " .. #npcs .. " walkby NPCs")

    local count = 0
    for _, npc in ipairs(npcs) do
        safe("giveFlyerToNpc", function()
            if not npc:IsValid() then return end
            giveFlyerToNpc(npc)
            flyerCount = flyerCount + 1
            count = count + 1
        end)
    end
    log("Flyers distributed to " .. count .. " NPCs")
end

-- ============================================================
-- HOOK REGISTRATION
-- ============================================================
ExecuteWithDelay(3000, function()

    -- Counts NPCs that became customers
    registerHookOptional(
        "/Game/VideoStore/core/ai/pawn/AI_WalkBy_Character.AI_WalkBy_Character_C:Transform the Walker into a Client",
        function(self)
            safe("Walker into Client", function()
                clientCount = clientCount + 1
                log("New customer! (total today: " .. clientCount .. ")")
            end)
        end
    )

    -- Store open/close
    registerHookOptional(
        "/Game/VideoStore/asset/prop/opensign/OpenSign.OpenSign_C:Change Sign",
        function(self)
            safe("OpenSign Change Sign", function()
                local sign = self:get()
                local isOpen = sign["is Open"]

                if isOpen then
                    storeIsOpen = true
                    clientCount = 0
                    flyerCount  = 0
                    pendingNpcs = {}
                    updateChance()
                    log("Store opened - distributing flyers...")
                    giveFlyersToAll()
                else
                    storeIsOpen = false
                    log("Store closed - " .. clientCount .. " new customers, " .. flyerCount .. " flyers given today")
                end
            end)
        end
    )

    -- Reset on save reload
    registerHookOptional(
        "/Game/VideoStore/asset/outside/WeatherSystem.WeatherSystem_C:ReceiveBeginPlay",
        function()
            resetTrackers()
            debug("Save reloaded - trackers reset")
        end
    )

    -- Reset at end of day
    registerHookOptional(
        "/Game/VideoStore/core/gamemode/Core_Gamemode.Core_Gamemode_C:End of the day",
        function()
            resetTrackers()
            debug("Day ended - trackers reset")
        end
    )

    -- Tracks ingame time, processes NPC queue, updates chance hourly
    registerHookOptional(
        "/Game/VideoStore/asset/outside/WeatherSystem.WeatherSystem_C:Timer Event - Add one minute",
        function(self)
            safe("Weather timer", function()
                local ws = self:get()
                local hour   = ws["Hour"]
                local minute = ws["Minute"]
                currentMinute = hour * 60 + minute

                if not storeIsOpen then return end

                if minute == 0 then
                    updateChance()
                end

                local remaining = {}
                for _, entry in ipairs(pendingNpcs) do
                    if currentMinute >= entry.spawnMinute + CONFIG.flyerDelay then
                        safe("pending NPC flyer", function()
                            if not entry.npc:IsValid() then return end
                            giveFlyerToNpc(entry.npc)
                            flyerCount = flyerCount + 1
                            log("Flyer given to NPC (total: " .. flyerCount .. ")")
                        end)
                    else
                        table.insert(remaining, entry)
                    end
                end
                pendingNpcs = remaining
            end)
        end
    )

    log("Promotion-QoL active")
end)

-- ============================================================
-- NotifyOnNewObject: queue new walkby NPCs while store is open
-- ============================================================
NotifyOnNewObject(
    "/Game/VideoStore/core/ai/pawn/AI_WalkBy_Character.AI_WalkBy_Character_C",
    function(obj)
        if not storeIsOpen then return end
        table.insert(pendingNpcs, { npc = obj, spawnMinute = currentMinute })
    end
)

log("Promotion-QoL loaded.")
