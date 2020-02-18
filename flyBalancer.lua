local yieldTime = os.clock()
local function yield()
    coroutine.yield()
    --local YIELD_SPAN = 0.5
    --if os.clock() - yieldTime > YIELD_SPAN then
    --    os.queueEvent("yield")
    --    os.pullEvent("yield")
    --    yieldTime = os.clock()
    --end
end

local DEBUG_LOG_FILE = "./fly_debug.log"
if fs.exists(DEBUG_LOG_FILE) then fs.delete(DEBUG_LOG_FILE) end

local function printDebug(msg)
    msg = msg.."\n"
    print(msg)
    --local log = fs.open(DEBUG_LOG_FILE, "a")
    --log.write(msg)
    --log.close()
end

-- NEURAL INTERFACE REQUIRED
local modules = peripheral.find("neuralInterface")
if not modules then error("Must have a neural interface", 0) end

-- MODULES REQUIRED
if not modules.hasModule("plethora:sensor") then error("Must have a sensor", 0) end
if not modules.hasModule("plethora:scanner") then error("Must have a scanner", 0) end
if not modules.hasModule("plethora:introspection") then error("Must have an introspection module", 0) end
if not modules.hasModule("plethora:kinetic", 0) then error("Must have a kinetic agument", 0) end

-- DEBUG CONTROL
local DEBUGCALLS = false
local DEBUGINPUT = true

-- KILL SWITCH CONTROL
local stop = false

-- PLAYER DATA CACHE
local meta = modules.getMetaOwner()

local function refreshMeta()    
    os.pullEvent("refreshMeta")
    if DEBUGCALLS then printDebug("refresh meta") end
    meta = modules.getMetaOwner()
end

-- LOCATION / HEIGHT ABOVE GROUND CACHE
local scanned = modules.scan()
local function refreshScan()    
    os.pullEvent("refreshScan")
    if DEBUGCALLS then printDebug("refresh scan") end
    scanned = modules.scan()
end

-- LOCATION HELPER
local scanner_radius = 8
local scanner_width = scanner_radius*2 + 1

local function scannedAt(x,y,z)
    return scanned[scanner_width ^ 2 * (x + scanner_radius) + scanner_width * (y + scanner_radius) + (z + scanner_radius) + 1]
end

-- CONTROLS
local LIGHTSPEED = 4
local FASTER = 2
local FAST = 1
local NORMAL = 0.5
local SPEEDMODE = NORMAL

local MAX_THRUST = 0.2
local MIN_THRUST = 0.15
local ACTUAL_THRUST = (MAX_THRUST - MIN_THRUST) / 2

local MAX_PITCH = 90
local MIN_PITCH = -90
local ACTUAL_PITCH = (MAX_PITCH - MIN_PITCH) / 2


local fly = false
local flyActivatedTime = -1

local upLastPressedTime=-1
local downLastPressedTime=-1
local frontLastPressedTime=-1
local backLastPressedTime=-1
local rightLastPressedTime=-1
local leftLastPressedTime=-1
local KEY_UP_THRESHOLD = 0.3 --sec

local down = false
local up = false
local front = false
local back = false
local right = false
local left = false

local lastSpaceTime = -1
local spacePressed = false

local hover = false

local in_flight = false

local FLYCALLSSINCELASTCONTROL = 1

local function controls()
    local event, key, held = os.pullEvent("key")
    FLYCALLSSINCELASTCONTROL = 0
    if DEBUGCALLS then printDebug("controls") end
    down = (os.clock()-downLastPressedTime)<KEY_UP_THRESHOLD
    up = (os.clock()-upLastPressedTime)<KEY_UP_THRESHOLD
    front = (os.clock()-frontLastPressedTime)<KEY_UP_THRESHOLD
    back = (os.clock()-backLastPressedTime)<KEY_UP_THRESHOLD
    right = (os.clock()-rightLastPressedTime)<KEY_UP_THRESHOLD
    left = (os.clock()-leftLastPressedTime)<KEY_UP_THRESHOLD

    if DEBUGINPUT then 
        if held then
            printDebug( "[key   ] " .. key .. "(held)")
        else
            printDebug( "[key   ] " .. key .. "(down)")
        end
    end

    if key == keys.k then
        stop = true
        print("K pressed, stopping program...")
    elseif key == keys.space and not held then    
        local spaceTime = os.clock()
        local diff = spaceTime - lastSpaceTime
        if (diff < 0.5) then
            fly = not fly
            spaceTime = -1
            if fly then 
                print("FLY MODE ENABLED")
                flyActivatedTime = os.clock()
                os.queueEvent("fly")
            else 
                print("FLY MODE DISABLED") 
            end                    
        end 
        lastSpaceTime = spaceTime    
    end

    -- FLIGHT RELATED
    -- period (.) => speedup
    if key == keys.period  then
        if SPEEDMODE == NORMAL then 
            SPEEDMODE = FAST
            print("Speed mode set to FAST")
        elseif SPEEDMODE == FAST then 
            SPEEDMODE = FASTER
            print("Speed mode set to FASTER")
        elseif SPEEDMODE == FASTER then 
            SPEEDMODE = LIGHTSPEED
            print("Speed mode set to LIGHTSPEED")
        else
            print("Speed mode is already maximal")
        end
    end
    -- comma (,) => slowdown
    if key == keys.comma then
        if SPEEDMODE == LIGHTSPEED then 
            SPEEDMODE = FASTER
            print("Speed mode set to FASTER")
        elseif SPEEDMODE == FASTER then 
            SPEEDMODE = FAST
            print("Speed mode set to FAST")
        elseif SPEEDMODE == FAST then 
            SPEEDMODE = NORMAL
            print("Speed mode set to NORMAL")
        else
            print("Speed mode is already minimal")
        end
    end
    -- shift => descente
    if key == keys.shift then
        down = true
        downLastPressedTime = os.clock()
    end
    -- space => montée 
    if key == keys.space then 
        up = true
        upLastPressedTime = os.clock()
    end
    -- W => en avant
    if key == keys.up then
        front = true
        frontLastPressedTime = os.clock()
    end
    -- S => en arrière 
    if key == keys.down then
        back = true
        backLastPressedTime = os.clock()
    end
    -- A => à gauche
    if key == keys.left then
        left = true
        leftLastPressedTime = os.clock()
    end
    -- D => à droite
    if key == keys.right then
        right = true
        rightLastPressedTime = os.clock()
    end
    -- on check le block sous les pieds du joueur
    in_flight = scannedAt(8,-1,8).name ~= "minecraft:air"
    if DEBUGINPUT then
        local pressed = ""
        if up then pressed = pressed.."UP " end
        if down then pressed = pressed.."DOWN " end
        if front then pressed = pressed.."FRONT " end
        if back then pressed = pressed.."BACK " end
        if right then pressed = pressed.."RIGHT " end
        if left then pressed = pressed.."LEFT " end
        printDebug(pressed)
    end
    -- on refresh nos données
    os.queueEvent("refreshMeta")
    os.queueEvent("refreshScan")
end


-- pitch = vertical
-- yaw = horizontal
-- both use -180 -> 180 degrees
-- lauynche(yaw, pitch, power)
-- i.e.: up = launch(0, -90, power)
-- north: -180|180
-- south: 0|360
-- east : -90|280
-- west : -280|90
--
--  0    --> 360
--  -360 --> 0
--
-- 2.W   3.N
--   \   /
--     X
--   /   \
-- 1.S   4.E     
-- Sens horaire so to the right = theta > 0
-- to the left theta < 0
--

local function addYaw(theta, delta)
    theta = theta + delta
    if theta < -360 then
        theta = theta + 360
    elseif theta > 360 then
        theta = theta - 360
    end
    return theta
end

local function flyMode()
    os.pullEvent("fly")
    
    if DEBUGCALLS then printDebug("fly") end
    if fly then
        FLYCALLSSINCELASTCONTROL = FLYCALLSSINCELASTCONTROL + 1
            -- si au sol => fly mode desactivé
        
        --if not in_flight and not up and (os.clock()-flyActivatedTime) > 0.5 then
        --    fly = false
        --    print("Ground reached, fly disabled")
        --    return
        --end

        -- YAW (horizontal)
        
        if front then 

            ACTUAL_PITCH = ACTUAL_PITCH + 5
            if ACTUAL_PITCH > MAX_PITCH then ACTUAL_PITCH = MAX_PITCH end
            front = false
        end

        if back then 
            ACTUAL_PITCH = ACTUAL_PITCH - 5
            if ACTUAL_PITCH < MIN_PITCH then ACTUAL_PITCH = MIN_PITCH end
            back = false
        end

        if right then 
            ACTUAL_THRUST = ACTUAL_THRUST + 0.01
            if ACTUAL_THRUST > MAX_THRUST then ACTUAL_THRUST = MAX_THRUST end
            right = false
        end 

        if left then 
            ACTUAL_THRUST = ACTUAL_THRUST - 0.01
            if ACTUAL_THRUST < MIN_THRUST then ACTUAL_THRUST = MIN_THRUST end
            left = false
        end 
        
        -- APPLY        
        
        if DEBUGINPUT then printDebug("fly: launch(\n\tyaw: "..meta.yaw..",\n\tpitch: "..ACTUAL_PITCH..",\n\tthrust: "..ACTUAL_THRUST..")") end
        modules.launch(meta.yaw, ACTUAL_PITCH, ACTUAL_THRUST)
        os.queueEvent("fly")
    end
end

local function untilKill(func, doesYield)
    while not stop do
        if doesYield then yield() end
        func()
    end
end

-- MAIN LOOP
print("FLY BALANCER program started, press K to stop")

parallel.waitForAny(
    function() 
        untilKill(refreshMeta, false)
    end,
    function() 
        untilKill(refreshScan, false)
    end,
    function() 
        untilKill(controls, false)
    end,
    function() 
        untilKill(flyMode, false)
    end--,
    --function() 
    --    untilKill(hoverMode)
    --end,
    --function() 
    --    untilKill(fallCushion)
    --end
)
