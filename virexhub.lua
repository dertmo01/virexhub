--[[
    VIREX ANTI-GUARD  -  Steal An Egg (placeId 107778070777162)
    Anti Hit, Auto Run Base, and Auto Fetch. Zero config.

    This file is only a loader. Everything lives in src/ and is fetched at run
    time, so the window and the features can be updated without every user
    re-pasting a new script -- and so each part stays small enough to read.

    Loader notes, learned the hard way:
      * Modules are fetched with cache-busting off and in dependency order.
        Order matters twice: log first, because every module logs during load;
        transport before antihit, because antihit calls into transport.
      * Each fetch is wrapped separately. If one file 404s the user gets a
        named error instead of a nil-index crash 300 lines into someone else's
        code, which is what makes this debuggable at all.
      * game:HttpGet caches aggressively on some executors, so SCRIPT_URL is
        appended with a per-load stamp to guarantee a fresh copy after an edit.
]]
local BASE = "https://raw.githubusercontent.com/dertmo01/virexhub/master/"

local stamp   = tostring(os.clock()) .. tostring(math.random())
local fetched = {}

local function fetch(path)
    local url = BASE .. path
    local ok, src = pcall(function() return game:HttpGet(url, true) end)
    if not ok or type(src) ~= "string" or #src < 10 then
        error(("Virex: could not fetch %s\n\nThe URL is:\n%s\n\n" ..
               "If you just pushed an update, wait ~30s and reload."):format(path, url), 0)
    end
    fetched[#fetched + 1] = path
    local chunk, err
    if loadstring then chunk, err = loadstring(src, "@" .. path) else chunk, err = load(src, "@" .. path) end
    if not chunk then
        error("Virex: syntax error in " .. path .. "\n" .. tostring(err), 0)
    end
    return chunk()
end

-- Load order is the dependency order.
local log       = fetch("src/core/log.lua")
local util      = fetch("src/core/util.lua")
local transport = fetch("src/core/transport.lua")
local antihit   = fetch("src/core/antihit.lua")
local eggs      = fetch("src/core/eggs.lua")
local selftest  = fetch("src/core/selftest.lua")
local probe     = fetch("src/core/probe.lua")
local kit       = fetch("src/ui/kit.lua")
local tabFeatures = fetch("src/tabs/features.lua")
local tabLogs     = fetch("src/tabs/logs.lua")
local tabConfig   = fetch("src/tabs/config.lua")

-- Build the window before the tabs so they have a page to draw into.
kit.currentTab = "Features"
local pageFeatures = kit.makePage("Features")
local pageLogs     = kit.makePage("Logs")
local pageConfig   = kit.makePage("Config")

kit.registerTab("Features", "\240\159\147\143", 1)
kit.registerTab("Logs",     "\240\159\147\145", 2)
kit.registerTab("Config",   "\226\154\149", 3)

local V = {
    log = log, util = util, transport = transport,
    antihit = antihit, eggs = eggs, selftest = selftest, probe = probe, ui = kit,
}
V.scriptURL = BASE .. "virexhub.lua?" .. stamp

tabFeatures.ui, tabFeatures.mods = kit, V
tabLogs.ui,     tabLogs.mods     = kit, V
tabConfig.ui,   tabConfig.mods   = kit, V

tabFeatures.build(pageFeatures)
tabLogs.build(pageLogs)
tabConfig.build(pageConfig)

-- Now that the init module exists on disk, wire it up. It is fetched last so
-- every module it hands references to is already loaded.
local init = fetch("src/init.lua")
init.hasLoadstring = (loadstring ~= nil) or (load ~= nil)
init.scriptURL  = V.scriptURL
init.wire(V)

kit.refreshTabs()
init.boot()

log.write("Loaded " .. #fetched .. " modules: " .. table.concat(fetched, ", "), log.INFO)
