local function printDebug(msg)
    msg = "["..os.date().."] "..msg.."\n"
    --print(msg)
    local log = fs.open(DEBUG_LOG_FILE, "a")
    log.write(msg)
    log.close()
end

-- NEURAL INTERFACE REQUIRED
local modules = peripheral.find("neuralInterface")
if not modules then error("Must have a neural interface", 0) end

-- MODULES REQUIRED
if not modules.hasModule("plethora:sensor") then error("Must have a sensor", 0) end
if not modules.hasModule("plethora:scanner") then error("Must have a scanner", 0) end
if not modules.hasModule("plethora:introspection") then error("Must have an introspection module", 0) end
if not modules.hasModule("plethora:kinetic", 0) then error("Must have a kinetic agument", 0) end

local stop = false


local function controls()
    local event, key, held = os.pullEvent("key")
    if key == keys.k then
        stop = true
        print("K pressed, stopping program...")
    end
end


local function calcGravity()
    
    local meta = modules.getMetaOwner()
    modules.launch(0, -90, 4)
    os.sleep(1)
    meta = modules.getMetaOwner()
    local speedY = meta.motionY
    os.sleep(1)
    meta = modules.getMetaOwner()
    local acceleration = meta.motionY - speedY
    print("Gravity on this planet is "..acceleration.." blocks per second.")
    stop = true 
end

local function untilKill(func, doesYield)
    while not stop do
        if doesYield then yield() end
        func()
    end
end

-- MAIN LOOP
print("whatgravity program started, press K to stop")

parallel.waitForAny(
    function() 
        untilKill(controls, false)
    end,
    function() 
        untilKill(calcGravity, false)
    end
)
