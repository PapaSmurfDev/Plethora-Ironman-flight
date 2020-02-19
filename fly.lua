-- fly system mk III
-- created and tested by Helldragger, have fun with it!

local function printDebug(msg)
    msg = msg.."\n"
    print(msg)
end

-- NEURAL INTERFACE REQUIRED
local modules = peripheral.find("neuralInterface")
if not modules then error("Must have a neural interface", 0) end

-- MODULES REQUIRED
if not modules.hasModule("plethora:sensor") then error("Must have a sensor", 0) end 
if not modules.hasModule("plethora:introspection") then error("Must have an introspection module", 0) end
if not modules.hasModule("plethora:kinetic", 0) then error("Must have a kinetic agument", 0) end
if not modules.hasModule("plethora:glasses") then error("The overlay glasses are missing", 0) end

-- KILL SWITCH CONTROL
local stop = false

-- PLAYER DATA CACHE
local meta = modules.getMetaOwner()

local function refreshMeta()    
    os.pullEvent("refreshMeta")
    if DEBUGCALLS then printDebug("refresh meta") end
    meta = modules.getMetaOwner()
end

-- CONTROLS
local LIGHTSPEED = 4
local FASTER = 2.5
local FAST = 1
local NORMAL = 0.2
local SPEEDMODE = NORMAL

local MAX_THRUST = SPEEDMODE
local MIN_THRUST = 0
local THRUST_GRADIENT = 0.01
local ACTUAL_THRUST = 0.15

local MAX_PITCH = 90
local MIN_PITCH = -90
local PITCH_GRADIENT = 45/9 --(MAX_PITCH - MIN_PITCH) / 10 
local ACTUAL_PITCH = 90 --((MAX_PITCH - MIN_PITCH) / 2)+MIN_PITCH


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

local FLYCALLSSINCELASTCONTROL = 1

local function addPitch(theta, delta)
    theta = math.fmod( theta + delta, 360 )
    if theta < 0 then
        theta = theta + 360
    end
    return theta
end


local function controls()
    local event, key, held = os.pullEvent("key")
    FLYCALLSSINCELASTCONTROL = 0
    down = (os.clock()-downLastPressedTime)<KEY_UP_THRESHOLD
    up = (os.clock()-upLastPressedTime)<KEY_UP_THRESHOLD
    front = (os.clock()-frontLastPressedTime)<KEY_UP_THRESHOLD
    back = (os.clock()-backLastPressedTime)<KEY_UP_THRESHOLD
    right = (os.clock()-rightLastPressedTime)<KEY_UP_THRESHOLD
    left = (os.clock()-leftLastPressedTime)<KEY_UP_THRESHOLD


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
            print("Speed mode set to FAST (warning: high altitude might lead to death by asphyxia)")
        elseif SPEEDMODE == FAST then 
            SPEEDMODE = FASTER
            print("Speed mode set to FASTER (WARNING: can reach deadly altitude VERY quick!)")
        elseif SPEEDMODE == FASTER then 
            SPEEDMODE = LIGHTSPEED
            print("Speed mode set to LIGHTSPEED (BIG WARNING: might reach deadly altitude in LESS than a few second!)")
        else
            print("Speed mode is already maximal (warning: high altitude might lead to death by asphyxia)")
        end
        MAX_THRUST = SPEEDMODE
        THRUST_GRADIENT = (MAX_THRUST - MIN_THRUST) / 10
    end
    -- comma (,) => slowdown
    if key == keys.comma then
        if SPEEDMODE == LIGHTSPEED then 
            SPEEDMODE = FASTER
            print("Speed mode set to FASTER (WARNING: can reach deadly altitude VERY quick!)")
        elseif SPEEDMODE == FASTER then 
            SPEEDMODE = FAST
            print("Speed mode set to FAST (warning: high altitude might lead to death by asphyxia)")
        elseif SPEEDMODE == FAST then 
            SPEEDMODE = NORMAL
            print("Speed mode set to NORMAL")
        else
            print("Speed mode is already minimal")
        end
        MAX_THRUST = SPEEDMODE
        THRUST_GRADIENT = (MAX_THRUST - MIN_THRUST) / 10
    end
    -- shift => descente
    if key == keys.leftShift then
        down = true
        downLastPressedTime = os.clock()
        ACTUAL_THRUST = ACTUAL_THRUST - THRUST_GRADIENT
        if ACTUAL_THRUST < MIN_THRUST then ACTUAL_THRUST = MIN_THRUST end

    end
    -- space => montée 
    if key == keys.space then 
        up = true
        upLastPressedTime = os.clock()
        ACTUAL_THRUST = ACTUAL_THRUST + THRUST_GRADIENT
        if ACTUAL_THRUST > MAX_THRUST then ACTUAL_THRUST = MAX_THRUST end

    end
    -- W => en avant
    if key == keys.w then
        front = true
        frontLastPressedTime = os.clock()
        ACTUAL_PITCH = addPitch(ACTUAL_PITCH, PITCH_GRADIENT)

    end
    -- S => en arrière 
    if key == keys.s then
        back = true
        backLastPressedTime = os.clock()
        ACTUAL_PITCH = addPitch(ACTUAL_PITCH, -PITCH_GRADIENT)

    end
    -- A => à gauche
    if key == keys.a then
        left = true
        leftLastPressedTime = os.clock()
    end
    -- D => à droite
    if key == keys.d then
        right = true
        rightLastPressedTime = os.clock()
    end
    -- on refresh nos données
    os.queueEvent("refreshMeta")
end


local function flyMode()
    os.pullEvent("fly")
    -- APPLY        
    if fly then
        FLYCALLSSINCELASTCONTROL = FLYCALLSSINCELASTCONTROL + 1    
        -- we shift the pitch in order to get up at 90 degrees and 0 at horizontal.
        modules.launch(meta.yaw,math.fmod( -ACTUAL_PITCH , 360), ACTUAL_THRUST)
        os.queueEvent("fly")
    end
end

local function getOrientation(pitch)

    --                 ^ 90
    --                 |
    --                 |
    -- 180 *-----------|------------> 0
    --                 |
    --                 |
    --                 * 270


    if  (pitch >= 0) then
        if (pitch < 45 or pitch >= 315) then
            return "front"
        elseif (pitch < 135 )  then
            return "up"
        elseif (pitch < 225 ) then
            return "back"
        else 
            return "down"
        end
    end
end


-- Get hold of the canvas
local interface = peripheral.wrap("back")
local canvas = interface.canvas()
canvas.clear()
-- And add a rectangle

local function round(value)
    return math.floor(value * 100)/100
end
local speedgroup = canvas.addGroup({10,0})
speedgroup.addText({10,10}, "Vertical")
local YSpeed =speedgroup.addText({10,20}, round(meta.motionY).."m/s")
speedgroup.addText({10,30}, "South-North")
local ZSpeed =speedgroup.addText({10,40}, round(meta.motionZ).."m/s")
speedgroup.addText({10,50}, "West-East")
local XSpeed = speedgroup.addText({10,60}, round(meta.motionX).."m/s")
speedgroup.addText({10,70}, "Thrust")
local ThrustSpeed = speedgroup.addText({10,80}, round(ACTUAL_THRUST).."%")
speedgroup.addText({10,90}, "Pitch")
local PitchSpeed = speedgroup.addText({10,100}, round(ACTUAL_PITCH).."degrees ("..getOrientation(ACTUAL_PITCH)..")")


local function overlay()
    YSpeed.setText(round(meta.motionY).."m/s")
    XSpeed.setText(round(meta.motionX).."m/s")
    ZSpeed.setText(round(meta.motionZ).."m/s")
    ThrustSpeed.setText((round(ACTUAL_THRUST)*100).."%")
    PitchSpeed.setText(round(ACTUAL_PITCH).."degrees ("..getOrientation(ACTUAL_PITCH)..")")
end


local function untilKill(func, doesYield)
    while not stop do
        if doesYield then coroutine.yield() end
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
        untilKill(controls, false)
    end,
    function() 
        untilKill(overlay, true)
    end,
    function() 
        untilKill(flyMode, false)
    end
)
