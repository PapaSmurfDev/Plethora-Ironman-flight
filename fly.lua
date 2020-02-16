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
    if DEBUGCALLS then print("refresh meta") end
    meta = modules.getMetaOwner()
end

-- LOCATION / HEIGHT ABOVE GROUND CACHE
local scanned = modules.scan()
local function refreshScan()
    if DEBUGCALLS then print("refresh scan") end
    scanned = modules.scan()
end

-- LOCATION HELPER
local scanner_radius = 8
local scanner_width = scanner_radius*2 + 1

local function scannedAt(x,y,z)
    return scanned[scanner_width ^ 2 * (x + scanner_radius) + scanner_width * (y + scanner_radius) + (z + scanner_radius) + 1]
end


-- CONTROLS

local fly = false
local flyActivatedTime = -1
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

local function controls()
    if DEBUGCALLS then print("controls") end
    local event, key, held = os.pullEvent()
    if DEBUGINPUT then 
        if event == "key" then 
            if held then
                print( "[key   ] " .. key .. "(held)")
            else
                print( "[key   ] " .. key .. "(down)")
            end
        elseif event == "key_up" then 
            print( "[key_up] " .. key) 
        end
    end
    if event == "key" and key == keys.k then
        stop = true
        print("K pressed, stopping program...")
        
    elseif event == "key" and key == keys.space and not held then    
        local spaceTime = os.clock()
        local diff = spaceTime - lastSpaceTime
        if (diff < 0.5) then
            fly = not fly
            spaceTime = -1
            if fly then 
                print("FLY MODE ENABLED")
                flyActivatedTime = os.clock()
            else 
                print("FLY MODE DISABLED") 
            end                    
        end 
        lastSpaceTime = spaceTime
        -- the space key launches you in whatever direction you are looking at
    
    end

    -- FLIGHT RELATED
    -- shift => descente
    if key == keys.shift then
        if event == "key" then 
            down = true 
        elseif event == "key_up" then
            down = false
        end
    end
    -- space => montée 
    if key == keys.space then 
        if event == "key" then
            up = true 
        elseif event == "key_up" then
            up = false
        end
    end
    -- W => en avant
    if key == keys.w then
        if event == "key" then
            front = true
        elseif event == "key_up" then
            front = false
        end
    end
    -- S => en arrière 
    if key == keys.s then
        if event == "key" then
            back = true
        elseif event == "key_up" then
            back = false
        end
    end
    -- A => à gauche
    if key == keys.a then
        if event == "key" then
            left = true
        elseif event == "key_up" then
            left = false
        end
    end
    -- D => à droite
    if key == keys.d then
        if event == "key" then
            right = true
        elseif event == "key_up" then
            right = false
        end
    end
    -- on check le block sous les pieds du joueur
    in_flight = scannedAt(8,0,8).name ~= "minecraft:air"
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
    if DEBUGCALLS then print("fly") end
    if fly then
        -- si au sol => fly mode desactivé
        
        if not in_flight and not up and (os.clock()-flyActivatedTime) > 0.5 then
            fly = false
            print("Ground reached, fly disabled")
            return
        end

        -- YAW (horizontal)
        local theta = 0
        if left then theta = addYaw(theta, -90) end
        if right then theta = addYaw(theta, 90) end
        if front then theta = addYaw(theta, 0) end
        if back then theta = addYaw(theta, 180) end
        theta = addYaw(meta.yaw, theta)

        -- PITCH (vertical)
        pitch = 0
        if up then pitch = -90 end
        if down then pitch = 90 end
        if left or right or front or back then pitch = pitch *1/4 end
        pitch =  meta.pitch + pitch

        -- POWER (speed)
        power = (meta.motionY^2 + meta.motionX^2)^0.5
        
        if left or right or front or back then power = power+0.1 end
        if up or down then power = power+0.3 end
        local MAXSPEED = 1
        power = math.min(MAXSPEED - power, 0)
        
        -- APPLY
        modules.launch(theta, pitch, power)
    end
end

local function hoverMode()
    if DEBUGCALLS then print("hover") end
    if hover then
        local mY = meta.motionY
        mY = (mY - 0.138) / 0.8
        if mY > 0.5 or mY < 0 then
            local sign = 1
            if mY < 0 then sign = -1 end
            modules.launch(meta.yaw, 90 * sign, math.min(4, math.abs(mY)))
        end
    end
end


local function fallCushion()
    if DEBUGCALLS then print("fall cushion") end
    if in_flight and not down and not up and meta.motionY < -0.3 then
        for y = 0, -8, -1 do
            local block = scannedAt(8,y,8)
            if block.name ~= "minecraft:air" then
                modules.launch( meta.yaw,
                                -90, 
                                math.min(4, meta.motionY / -0.5))
                break
            end
        end
    end
end

local function untilKill(func, doesYield)
    while not stop do
        if doesYield then yield() end
        func()
    end
end

-- MAIN LOOP
print("FLY program started, press K to stop")

parallel.waitForAny(
    function() 
        untilKill(refreshMeta, true)
    end,
    function() 
        untilKill(refreshScan, true)
    end,
    function() 
        untilKill(controls, false)
    end,
    function() 
        untilKill(flyMode, true)
    end--,
    --function() 
    --    untilKill(hoverMode)
    --end,
    --function() 
    --    untilKill(fallCushion)
    --end
)
