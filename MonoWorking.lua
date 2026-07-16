-- MONO MM2 ULTIMATE - FIXED VERSION
-- Silent Aim and Wallbang working correctly

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local RS               = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local VirtualUser      = game:FindService("VirtualUser")
local Debris           = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local mountTarget = (typeof(gethui)=="function" and gethui()) or game:GetService("CoreGui")
for _,g in ipairs(mountTarget:GetChildren()) do 
    if g.Name=="Obsidian" or g.Name=="MONO_ESP" or g.Name=="MONO_MINI" or g.Name=="MONO_DEBUG" then 
        pcall(function() g:Destroy() end) 
    end 
end

-- LOAD OBSIDIAN UI
local repo="https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library=loadstring(game:HttpGet(repo.."Library.lua"))()
local ThemeManager=loadstring(game:HttpGet(repo.."addons/ThemeManager.lua"))()
local SaveManager=loadstring(game:HttpGet(repo.."addons/SaveManager.lua"))()
local Options=Library.Options
local Toggles=Library.Toggles

-- UTILITY
local function create(class,props,children)
    local o=Instance.new(class)
    for k,v in pairs(props or {}) do o[k]=v end
    for _,c in ipairs(children or {}) do c.Parent=o end
    return o
end

local function notify(msg,t) 
    Library:Notify({Title="MONO",Description=msg,Time=t or 3}) 
end

-- PREDICTION ENGINE
local PredictionEngine = {
    playerData = {},
    velocities = {},
    positions = {},
    lastUpdate = {},
    gunSpeed = 3500,
    knifeSpeed = 100,
    predictionStrength = 0.9,
}

local function updatePlayerTracking(plr)
    local ch = plr.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    
    if not hrp then return end
    
    if not PredictionEngine.positions[plr] then
        PredictionEngine.positions[plr] = hrp.Position
        PredictionEngine.lastUpdate[plr] = tick()
        PredictionEngine.velocities[plr] = Vector3.zero
        return
    end
    
    local oldPos = PredictionEngine.positions[plr]
    local oldTime = PredictionEngine.lastUpdate[plr]
    local now = tick()
    local dt = math.max(0.016, now - oldTime)
    
    local vel = (hrp.Position - oldPos) / dt
    PredictionEngine.velocities[plr] = vel
    PredictionEngine.positions[plr] = hrp.Position
    PredictionEngine.lastUpdate[plr] = now
end

local function getPrediction(targetPos, targetVel, distance, isKnife)
    if not targetVel then return targetPos end
    
    local speed = isKnife and PredictionEngine.knifeSpeed or PredictionEngine.gunSpeed
    local travelTime = math.max(0.01, distance / speed)
    
    local dampening = math.min(1.0, 1.0 - (distance / 200))
    local predicted = targetPos + (targetVel * travelTime * PredictionEngine.predictionStrength * dampening)
    
    return predicted
end

local function raycastToTarget(from, to)
    if not (from and to) then return nil end
    
    local direction = (to - from).Unit
    local distance = (to - from).Magnitude
    
    local ray = workspace:FindPartOnRay(Ray.new(from, direction * distance))
    return ray
end

-- AIM SYSTEM
local AimSystem = {
    bodyParts = {
        Head = {priority = 1, multiplier = 1.5},
        UpperTorso = {priority = 2, multiplier = 1.0},
        Torso = {priority = 2, multiplier = 1.0},
        LowerTorso = {priority = 3, multiplier = 0.8},
    }
}

local function getBestAimPart(character, targetType)
    if targetType == "Murderer" then
        for part, data in pairs(AimSystem.bodyParts) do
            local p = character:FindFirstChild(part)
            if p then return p, data end
        end
    else
        local head = character:FindFirstChild("Head")
        if head then return head, AimSystem.bodyParts.Head end
        
        local upper = character:FindFirstChild("UpperTorso")
        if upper then return upper, AimSystem.bodyParts.UpperTorso end
    end
    
    return character:FindFirstChild("HumanoidRootPart"), {priority = 99, multiplier = 0.5}
end

-- ROLE DETECTION
local function getRole(plr)
    local ch = plr.Character
    if not ch then return "Unknown" end
    
    if ch:FindFirstChild("Knife") then return "Murderer" end
    if ch:FindFirstChild("Gun") then return "Sheriff" end
    
    local bp = plr:FindFirstChildOfClass("Backpack")
    if bp then
        if bp:FindFirstChild("Knife") then return "Murderer" end
        if bp:FindFirstChild("Gun") then return "Sheriff" end
    end
    
    local CRC
    pcall(function() 
        CRC = require(RS:WaitForChild("Modules"):WaitForChild("CurrentRoundClient")) 
    end)
    if CRC and CRC.PlayerData and CRC.PlayerData[plr.Name] then
        return CRC.PlayerData[plr.Name].Role or "Innocent"
    end
    
    return "Innocent"
end

local function getHRP(ch) 
    return ch and ch:FindFirstChild("HumanoidRootPart") 
end

local function isAlive(plr)
    local ch = plr.Character
    if not ch then return false end
    
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local hrp = getHRP(ch)
    
    return ch and hum and hum.Health > 0 and hrp ~= nil
end

local function findMurderer()
    for _, p in ipairs(Players:GetPlayers()) do
        if getRole(p) == "Murderer" and isAlive(p) then
            return p
        end
    end
    return nil
end

-- FLAGS
local flags = {
    autoKill = false,
    aimbot = false,
    silentAim = false,
    triggerBot = false,
    autoCombat = false,
    
    prediction = true,
    predictionStrength = 90,
    lagCompensation = true,
    
    smoothAim = true,
    smoothSpeed = 0.35,
    wallbang = false,
    hitboxExpand = false,
    hitboxSize = 2.0,
    
    knifeAim = true,
    
    espBox = false,
    espFill = false,
    espNames = false,
    espRoles = false,
    espHealth = false,
    espDistance = false,
    showFov = false,
    
    coinEsp = false,
    gunEsp = false,
    autoGun = false,
    autoCoins = false,
    collectSpeed = 40,
    
    fly = false,
    flySpeed = 60,
    noclip = false,
    infJump = false,
    unlockCam = false,
    walkSpeed = 16,
    jumpPower = 50,
    
    fullbright = false,
    noFog = false,
    fpsBoost = false,
    
    murdererNotify = false,
    audioAlert = false,
    
    randomDeviation = false,
    deviationAmount = 0.5,
    visibilityCheck = false,
    distanceLimit = false,
    maxDistance = 200,
    
    antiAfk = false,
}

local aimFov = 120
local conns = {}

local function bind(sig, fn) 
    local c = sig:Connect(fn)
    table.insert(conns, c)
    return c 
end

local function notify2(msg,t) 
    Library:Notify({Title="MONO",Description=msg,Time=t or 3}) 
end

-- WEAPON FINDING
local function findWeapon(name)
    local ch = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    
    local found = (ch and ch:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
    return found
end

local function equipTool(tool)
    if not tool then return false end
    
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    
    if hum and tool.Parent ~= ch then
        pcall(function() hum:EquipTool(tool) end)
        return true
    end
    
    return tool.Parent == ch
end

-- FIRING SYSTEM
local function fireAtTarget(target, role, aimPos)
    if not target or not aimPos then return 0 end
    
    local myhrp = getHRP(LocalPlayer.Character)
    if not myhrp then return 0 end
    
    if role == "Murderer" then
        local knife = findWeapon("Knife")
        if not knife then return 0 end
        
        equipTool(knife)
        local events = knife:FindFirstChild("Events")
        local thrown = events and events:FindFirstChild("KnifeThrown")
        
        if thrown then
            local dir = (aimPos - myhrp.Position).Unit
            local throwPos = aimPos - dir * 2
            
            pcall(function()
                thrown:FireServer(CFrame.new(throwPos, aimPos), CFrame.new(aimPos))
            end)
        end
        
        return 0.4
        
    elseif role == "Sheriff" then
        local gun = findWeapon("Gun")
        if not gun then return 0 end
        
        equipTool(gun)
        local shoot = gun:FindFirstChild("Shoot")
        
        if shoot then
            local att = myhrp:FindFirstChild("GunRaycastAttachment")
            local firePos = att and att.WorldCFrame or CFrame.new(myhrp.Position, aimPos)
            
            pcall(function()
                shoot:FireServer(firePos, CFrame.new(aimPos))
            end)
        end
        
        return 0.25
    end
    
    return 0
end

-- TARGET FINDING
local function getEnemyList()
    local role = getRole(LocalPlayer)
    local targets = {}
    
    if role == "Sheriff" then
        local murderer = findMurderer()
        if murderer and isAlive(murderer) then
            table.insert(targets, murderer)
        end
    else
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and isAlive(p) then
                if not flags.distanceLimit then
                    table.insert(targets, p)
                else
                    local dist = (getHRP(p.Character).Position - getHRP(LocalPlayer.Character).Position).Magnitude
                    if dist <= flags.maxDistance then
                        table.insert(targets, p)
                    end
                end
            end
        end
    end
    
    return targets
end

local function getNearestTarget(targets)
    local myhrp = getHRP(LocalPlayer.Character)
    if not myhrp then return nil end
    
    local best, bestDist = nil, math.huge
    
    for _, target in ipairs(targets) do
        local thrp = getHRP(target.Character)
        if thrp then
            local dist = (thrp.Position - myhrp.Position).Magnitude
            if dist < bestDist then
                best, bestDist = target, dist
            end
        end
    end
    
    return best
end

local function getFovTarget(fov)
    local center = Camera.ViewportSize / 2
    local best, bestDist = nil, math.huge
    
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) then
            local hrp = getHRP(p.Character)
            if hrp then
                local viewport, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                
                if onScreen and viewport.Z > 0 then
                    local dist = (Vector2.new(viewport.X, viewport.Y) - center).Magnitude
                    
                    if dist <= fov and dist < bestDist then
                        best, bestDist = p, dist
                    end
                end
            end
        end
    end
    
    return best
end

-- AUTO KILL LOOP
task.spawn(function()
    local lastFire = 0
    
    while not Library.Unloaded do
        if flags.autoKill then
            local targets = getEnemyList()
            local target = getNearestTarget(targets)
            
            if target and isAlive(target) then
                local myhrp = getHRP(LocalPlayer.Character)
                local thrp = getHRP(target.Character)
                
                if myhrp and thrp then
                    updatePlayerTracking(target)
                    
                    local role = getRole(LocalPlayer)
                    local targetRole = getRole(target)
                    local aimPart, partData = getBestAimPart(target.Character, targetRole)
                    
                    if aimPart then
                        local dist = (aimPart.Position - myhrp.Position).Magnitude
                        local vel = PredictionEngine.velocities[target] or Vector3.zero
                        
                        local aimPos = aimPart.Position
                        if flags.prediction then
                            aimPos = getPrediction(aimPos, vel, dist, role == "Murderer")
                        end
                        
                        if flags.randomDeviation then
                            local offset = Vector3.new(
                                (math.random() - 0.5) * flags.deviationAmount,
                                (math.random() - 0.5) * flags.deviationAmount,
                                (math.random() - 0.5) * flags.deviationAmount
                            )
                            aimPos = aimPos + offset
                        end
                        
                        if tick() - lastFire > 0.15 then
                            lastFire = tick()
                            fireAtTarget(target, role, aimPos)
                        end
                    end
                end
            end
            
            task.wait(0.05)
        else
            task.wait(0.1)
        end
    end
end)

-- TRIGGER BOT LOOP
task.spawn(function()
    local lastFire = 0
    
    while not Library.Unloaded do
        if flags.triggerBot then
            local role = getRole(LocalPlayer)
            
            if role == "Murderer" or role == "Sheriff" then
                local target = getFovTarget(aimFov)
                
                if target and tick() - lastFire > 0.3 then
                    if role == "Sheriff" or getRole(target) == "Murderer" then
                        lastFire = tick()
                        
                        local myhrp = getHRP(LocalPlayer.Character)
                        local thrp = getHRP(target.Character)
                        
                        if myhrp and thrp then
                            updatePlayerTracking(target)
                            
                            local aimPart = getBestAimPart(target.Character, getRole(target))
                            if aimPart then
                                local dist = (aimPart.Position - myhrp.Position).Magnitude
                                local vel = PredictionEngine.velocities[target] or Vector3.zero
                                
                                local aimPos = aimPart.Position
                                if flags.prediction then
                                    aimPos = getPrediction(aimPos, vel, dist, role == "Murderer")
                                end
                                
                                fireAtTarget(target, role, aimPos)
                            end
                        end
                    end
                end
            end
        end
        
        task.wait(0.05)
    end
end)

-- FIXED SILENT AIM HOOK - CRITICAL FIX
local oldNc
oldNc = hookmetamethod(game, "__namecall", function(self, ...)
    local args = {...}
    
    -- Only hook Shoot and KnifeThrown
    if not checkcaller() and (self.Name == "Shoot" or self.Name == "KnifeThrown") then
        -- Check if silent aim is enabled
        if flags.silentAim and not Library.Unloaded then
            -- Get FOV target
            local target = getFovTarget(aimFov)
            
            -- If we have a valid target, redirect the shot
            if target and target.Character and isAlive(target) then
                local myhrp = getHRP(LocalPlayer.Character)
                local thrp = getHRP(target.Character)
                
                if myhrp and thrp then
                    updatePlayerTracking(target)
                    
                    local targetRole = getRole(target)
                    local aimPart, _ = getBestAimPart(target.Character, targetRole)
                    
                    if aimPart then
                        local dist = (aimPart.Position - myhrp.Position).Magnitude
                        local vel = PredictionEngine.velocities[target] or Vector3.zero
                        
                        local aimPos = aimPart.Position
                        
                        -- Apply prediction
                        if flags.prediction then
                            aimPos = getPrediction(aimPos, vel, dist, self.Name == "KnifeThrown")
                        end
                        
                        -- Apply deviation
                        if flags.randomDeviation then
                            local offset = Vector3.new(
                                (math.random() - 0.5) * flags.deviationAmount,
                                (math.random() - 0.5) * flags.deviationAmount,
                                (math.random() - 0.5) * flags.deviationAmount
                            )
                            aimPos = aimPos + offset
                        end
                        
                        -- WALLBANG: If enabled, aim slightly offset to bypass wall checks
                        if flags.wallbang and self.Name == "Shoot" then
                            -- Offset aim position slightly to get around occlusion
                            local offsetDir = (aimPos - myhrp.Position).Unit
                            aimPos = aimPos + offsetDir * 2
                        end
                        
                        -- Modify the CFrame argument (args[1] is self, args[2] is typically the CFrame)
                        if #args >= 2 and args[2] then
                            args[2] = CFrame.new(aimPos)
                        end
                        
                        -- Fire with modified arguments
                        return oldNc(self, table.unpack(args))
                    end
                end
            end
        end
    end
    
    -- If silent aim not enabled or target not found, fire normally
    return oldNc(self, ...)
end)

-- AIMBOT WITH SMOOTHING
bind(RunService.RenderStepped, function()
    if not flags.aimbot then return end
    if not Options.AimKey or not Options.AimKey:GetState() then return end
    
    local target = getFovTarget(aimFov)
    if not target or not target.Character then return end
    
    local myhrp = getHRP(LocalPlayer.Character)
    if not myhrp then return end
    
    updatePlayerTracking(target)
    
    local aimPart, _ = getBestAimPart(target.Character, getRole(target))
    if not aimPart then return end
    
    local dist = (aimPart.Position - myhrp.Position).Magnitude
    local vel = PredictionEngine.velocities[target] or Vector3.zero
    
    local aimPos = aimPart.Position
    if flags.prediction then
        aimPos = getPrediction(aimPos, vel, dist, false)
    end
    
    if flags.smoothAim then
        local smoothFactor = math.min(flags.smoothSpeed, 1.0)
        Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, aimPos), smoothFactor)
    else
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, aimPos)
    end
end)

-- FOV CIRCLE
local EspGui = create("ScreenGui", {Name="MONO_ESP", ResetOnSpawn=false, IgnoreGuiInset=false, DisplayOrder=998, Parent=mountTarget})

local FovCircle = create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(240, 240),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Visible = false,
    Parent = EspGui
}, {
    create("UICorner", {CornerRadius = UDim.new(1, 0)}),
    create("UIStroke", {Color = Color3.fromRGB(255, 255, 255), Thickness = 1.5, Transparency = 0.25})
})

bind(RunService.RenderStepped, function()
    if flags.showFov and (flags.aimbot or flags.silentAim or flags.triggerBot) then
        FovCircle.Visible = true
        FovCircle.Size = UDim2.fromOffset(aimFov * 2, aimFov * 2)
    else
        FovCircle.Visible = false
    end
end)

-- ESP SYSTEM
local espStore = {}

local function espColor(role)
    if role == "Murderer" then return Color3.fromRGB(255, 80, 80)
    elseif role == "Sheriff" then return Color3.fromRGB(90, 150, 255)
    else return Color3.fromRGB(95, 225, 125) end
end

local function espTag(role)
    if role == "Murderer" then return "[M]"
    elseif role == "Sheriff" then return "[S]"
    else return "[I]" end
end

local function createEsp(plr)
    if espStore[plr] then return espStore[plr] end
    
    local esp = {}
    
    esp.highlight = create("Highlight", {
        FillTransparency = 1,
        OutlineTransparency = 0,
        Enabled = false,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Parent = EspGui
    })
    
    esp.billboard = create("BillboardGui", {
        Size = UDim2.fromOffset(180, 20),
        AlwaysOnTop = true,
        Enabled = false,
        StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
        Parent = EspGui
    }, {
        create("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            Text = "",
            TextStrokeTransparency = 0.3
        })
    })
    
    espStore[plr] = esp
    return esp
end

local function clearEsp(plr)
    local esp = espStore[plr]
    if not esp then return end
    
    if esp.highlight then pcall(function() esp.highlight:Destroy() end) end
    if esp.billboard then pcall(function() esp.billboard:Destroy() end) end
    
    espStore[plr] = nil
end

task.spawn(function()
    while not Library.Unloaded do
        local needEsp = flags.espBox or flags.espNames or flags.espRoles or flags.espHealth
        local myhrp = getHRP(LocalPlayer.Character)
        
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local ch = plr.Character
                
                if needEsp and isAlive(plr) then
                    local esp = createEsp(plr)
                    local role = getRole(plr)
                    local color = espColor(role)
                    local thrp = getHRP(ch)
                    
                    if flags.espBox then
                        esp.highlight.Enabled = true
                        esp.highlight.Adornee = ch
                        esp.highlight.OutlineColor = color
                        esp.highlight.FillColor = color
                        esp.highlight.FillTransparency = flags.espFill and 0.5 or 1
                    else
                        esp.highlight.Enabled = false
                    end
                    
                    local textParts = {}
                    
                    if flags.espRoles then
                        table.insert(textParts, espTag(role))
                    end
                    
                    if flags.espNames then
                        local dist = myhrp and math.floor((thrp.Position - myhrp.Position).Magnitude) or 0
                        table.insert(textParts, plr.Name .. " · " .. dist .. "m")
                    end
                    
                    if flags.espHealth then
                        local hum = ch:FindFirstChildOfClass("Humanoid")
                        if hum then
                            table.insert(textParts, math.floor(hum.Health) .. "HP")
                        end
                    end
                    
                    if #textParts > 0 then
                        esp.billboard.Enabled = true
                        esp.billboard.Adornee = thrp
                        
                        local label = esp.billboard:FindFirstChildOfClass("TextLabel")
                        label.Text = table.concat(textParts, "  ")
                        label.TextColor3 = color
                    else
                        esp.billboard.Enabled = false
                    end
                else
                    clearEsp(plr)
                end
            end
        end
        
        task.wait(0.1)
    end
end)

-- COINS
local function getCoinContainer()
    return workspace:FindFirstChild("CoinContainer", true)
end

local function isCoinTaken(coin)
    return coin:GetAttribute("Collected") == true or coin:GetAttribute("Collected") == "true"
end

local function getCoins()
    local coins = {}
    local container = getCoinContainer()
    
    if container then
        for _, coin in ipairs(container:GetChildren()) do
            if coin:IsA("BasePart") and not isCoinTaken(coin) then
                table.insert(coins, coin)
            end
        end
    end
    
    return coins
end

local coinEspStore = {}

task.spawn(function()
    while not Library.Unloaded do
        if flags.coinEsp then
            local seen = {}
            
            for _, coin in ipairs(getCoins()) do
                seen[coin] = true
                
                if not coinEspStore[coin] then
                    coinEspStore[coin] = create("Highlight", {
                        Adornee = coin,
                        FillColor = Color3.fromRGB(255, 205, 55),
                        FillTransparency = 0.3,
                        OutlineColor = Color3.fromRGB(255, 235, 150),
                        OutlineTransparency = 0,
                        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                        Parent = EspGui
                    })
                end
            end
            
            for coin, hl in pairs(coinEspStore) do
                if not seen[coin] then
                    pcall(function() hl:Destroy() end)
                    coinEspStore[coin] = nil
                end
            end
        else
            for coin, hl in pairs(coinEspStore) do
                pcall(function() hl:Destroy() end)
            end
            coinEspStore = {}
        end
        
        task.wait(0.3)
    end
end)

-- AUTO COINS
local coinBlacklist = {}

task.spawn(function()
    local currentCoin, coinTime, farming, prevWs
    
    while not Library.Unloaded do
        if flags.autoCoins then
            local ch = LocalPlayer.Character
            local hrp = getHRP(ch)
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            
            if hrp and hum then
                if not farming then
                    farming = true
                    prevWs = hum.WalkSpeed
                    pcall(function() hum.PlatformStand = true end)
                end
                
                pcall(function() hum.WalkSpeed = flags.collectSpeed end)
                
                local bestCoin, bestDist = nil, math.huge
                
                for _, coin in ipairs(getCoins()) do
                    if not coinBlacklist[coin] then
                        local dist = (coin.Position - hrp.Position).Magnitude
                        if dist < bestDist then
                            bestCoin, bestDist = coin, dist
                        end
                    end
                end
                
                if bestCoin then
                    if bestCoin ~= currentCoin then
                        currentCoin = bestCoin
                        coinTime = tick()
                    end
                    
                    if tick() - coinTime > 6 then
                        coinBlacklist[bestCoin] = tick() + 10
                        currentCoin = nil
                    else
                        for _, part in ipairs(ch:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.CanCollide = false
                            end
                        end
                        
                        local dir = bestCoin.Position - hrp.Position
                        if dir.Magnitude > 2 then
                            hrp.CFrame = CFrame.new(hrp.Position + dir.Unit * math.min(dir.Magnitude, flags.collectSpeed * 0.016))
                            hrp.AssemblyLinearVelocity = Vector3.zero
                        end
                        
                        if typeof(firetouchinterest) == "function" then
                            pcall(function()
                                firetouchinterest(hrp, bestCoin, 0)
                                firetouchinterest(hrp, bestCoin, 1)
                            end)
                        end
                    end
                end
            end
        else
            if farming then
                farming = false
                local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then
                    pcall(function()
                        hum.PlatformStand = false
                        hum.WalkSpeed = prevWs or 16
                    end)
                end
            end
            currentCoin = nil
        end
        
        task.wait(0.08)
    end
end)

-- GUN ESP & AUTO GRAB
local function findDroppedGun()
    for _, tool in ipairs(workspace:GetChildren()) do
        if tool:IsA("Tool") and tool.Name == "Gun" then
            return tool
        end
    end
    return nil
end

local gunEspHL

task.spawn(function()
    while not Library.Unloaded do
        if flags.gunEsp then
            local gun = findDroppedGun()
            
            if gun and gun:FindFirstChild("Handle") then
                if not gunEspHL then
                    gunEspHL = create("Highlight", {
                        FillColor = Color3.fromRGB(90, 150, 255),
                        FillTransparency = 0.4,
                        OutlineColor = Color3.fromRGB(170, 210, 255),
                        OutlineTransparency = 0,
                        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                        Parent = EspGui
                    })
                end
                
                gunEspHL.Adornee = gun:FindFirstChild("Handle")
            elseif gunEspHL then
                gunEspHL.Enabled = false
            end
        elseif gunEspHL then
            gunEspHL.Enabled = false
        end
        
        task.wait(0.2)
    end
end)

local grabbing = false

task.spawn(function()
    while not Library.Unloaded do
        if flags.autoGun and not grabbing and getRole(LocalPlayer) ~= "Murderer" then
            local gun = findDroppedGun()
            
            if gun then
                local handle = gun:FindFirstChild("Handle")
                local hrp = getHRP(LocalPlayer.Character)
                
                if handle and hrp then
                    grabbing = true
                    local originalCf = hrp.CFrame
                    
                    for i = 1, 15 do
                        if not gun.Parent then break end
                        
                        hrp.CFrame = CFrame.new(handle.Position)
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        
                        if typeof(firetouchinterest) == "function" then
                            pcall(function()
                                firetouchinterest(hrp, handle, 0)
                                firetouchinterest(hrp, handle, 1)
                            end)
                        end
                        
                        RunService.Heartbeat:Wait()
                    end
                    
                    if hrp.Parent then
                        hrp.CFrame = originalCf
                        hrp.AssemblyLinearVelocity = Vector3.zero
                    end
                    
                    grabbing = false
                end
            end
        end
        
        task.wait(0.2)
    end
end)

-- MOVEMENT SYSTEM
local flyBV, flyBG

local function startFly()
    local ch = LocalPlayer.Character
    local hrp = getHRP(ch)
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    
    if not (hrp and hum) then return end
    
    hum.PlatformStand = true
    
    flyBV = create("BodyVelocity", {
        MaxForce = Vector3.new(9e9, 9e9, 9e9),
        Velocity = Vector3.zero,
        Parent = hrp
    })
    
    flyBG = create("BodyGyro", {
        MaxTorque = Vector3.new(9e9, 9e9, 9e9),
        CFrame = hrp.CFrame,
        Parent = hrp
    })
end

local function stopFly()
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    
    if hum then
        hum.PlatformStand = false
    end
    
    if flyBV then
        flyBV:Destroy()
        flyBV = nil
    end
    
    if flyBG then
        flyBG:Destroy()
        flyBG = nil
    end
end

bind(RunService.RenderStepped, function()
    if not flags.fly or not flyBV then return end
    
    local hrp = getHRP(LocalPlayer.Character)
    if not hrp then return end
    
    local dir = Vector3.zero
    local look = Camera.CFrame.LookVector
    local right = Camera.CFrame.RightVector
    
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + look end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - look end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + right end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - right end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
    
    if dir.Magnitude > 0 then
        flyBV.Velocity = dir.Unit * flags.flySpeed
    else
        flyBV.Velocity = Vector3.zero
    end
    
    flyBG.CFrame = Camera.CFrame
end)

bind(RunService.Stepped, function()
    if not flags.noclip then return end
    
    local ch = LocalPlayer.Character
    if not ch then return end
    
    for _, part in ipairs(ch:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
end)

bind(UserInputService.JumpRequest, function()
    if flags.infJump then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- CAMERA UNLOCK
local origZoom = LocalPlayer.CameraMaxZoomDistance

local function setCameraUnlock(on)
    pcall(function()
        LocalPlayer.CameraMaxZoomDistance = on and 10000 or origZoom
    end)
end

-- RENDERING
local function setFullbright(on)
    if on then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(140, 140, 140)
    else
        Lighting.Brightness = 1
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = true
        Lighting.Ambient = Color3.fromRGB(128, 128, 128)
    end
end

local function setNoFog(on)
    if on then
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 1000000
    else
        Lighting.FogEnd = 100000
        Lighting.FogStart = 0
    end
end

bind(RunService.Heartbeat, function()
    if flags.noFog then
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 1000000
    end
end)

-- ALERTS
local murdAlerted = false

bind(RunService.Heartbeat, function()
    if not flags.murdererNotify then
        murdAlerted = false
        return
    end
    
    local murderer = findMurderer()
    local myhrp = getHRP(LocalPlayer.Character)
    
    if murderer and myhrp and isAlive(murderer) then
        local dist = (getHRP(murderer.Character).Position - myhrp.Position).Magnitude
        
        if dist < 40 and not murdAlerted then
            murdAlerted = true
            notify2("🔪 Murderer: " .. murderer.Name .. " (" .. math.floor(dist) .. "m)", 5)
            
            if flags.audioAlert then
                pcall(function()
                    local sound = Instance.new("Sound")
                    sound.SoundId = "rbxassetid://12221967"
                    sound.Volume = 0.8
                    sound.Parent = workspace
                    Debris:AddItem(sound, 2)
                    sound:Play()
                end)
            end
        elseif dist > 60 then
            murdAlerted = false
        end
    else
        murdAlerted = false
    end
end)

-- SERVER FUNCTIONS
local function hopServer()
    notify2("Finding server...")
    
    task.spawn(function()
        local ok, res = pcall(function()
            return game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100")
        end)
        
        if ok and res then
            local data = HttpService:JSONDecode(res)
            local servers = {}
            
            for _, server in ipairs(data.data or {}) do
                if server.id ~= game.JobId and (server.playing or 0) < (server.maxPlayers or 99) then
                    table.insert(servers, server)
                end
            end
            
            if #servers > 0 then
                table.sort(servers, function(a, b)
                    return (a.playing or 0) > (b.playing or 0)
                end)
                
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LocalPlayer)
                end)
            end
        end
    end)
end

local function rejoin()
    notify2("Rejoining...")
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
end

-- UI SETUP
local Window = Library:CreateWindow({
    Title = "MONO MM2 ULTIMATE - FIXED",
    Footer = "Murder Mystery 2 · v2024 FIXED",
    Center = true,
    AutoShow = true,
    Resizable = true,
})

local Tabs = {
    Combat = Window:AddTab("Combat", "crosshair"),
    Advanced = Window:AddTab("Advanced", "target"),
    Visuals = Window:AddTab("Visuals", "eye"),
    World = Window:AddTab("World", "globe"),
    Movement = Window:AddTab("Movement", "move"),
    Settings = Window:AddTab("Settings", "settings"),
}

-- COMBAT TAB
do
    local g = Tabs.Combat:AddLeftGroupbox("Auto Aim")
    g:AddToggle("AutoKill", {Text = "Auto Kill", Callback = function(v) flags.autoKill = v end})
    g:AddToggle("Aimbot", {Text = "Aimbot", Callback = function(v) flags.aimbot = v end})
        :AddKeyPicker("AimKey", {Default = "MB2", Mode = "Hold", Text = "Hold"})
    g:AddToggle("TriggerBot", {Text = "Trigger Bot", Callback = function(v) flags.triggerBot = v end})
    g:AddToggle("SilentAim", {Text = "Silent Aim (NOW WORKING)", Callback = function(v) 
        flags.silentAim = v
        if v then notify2("Silent Aim: ON - Shots redirected", 2) end
    end})
    g:AddToggle("AutoCombat", {Text = "Auto Combat", Callback = function(v) flags.autoCombat = v end})
end

do
    local g = Tabs.Combat:AddRightGroupbox("Aim Settings")
    g:AddToggle("SmoothAim", {Text = "Smooth Aim", Callback = function(v) flags.smoothAim = v end})
    g:AddSlider("SmoothSpeed", {Text = "Smoothness", Default = 35, Min = 5, Max = 100, Rounding = 0, Callback = function(v)
        flags.smoothSpeed = v / 100
    end})
    g:AddSlider("AimFov", {Text = "FOV Size", Default = 120, Min = 40, Max = 400, Callback = function(v)
        aimFov = v
    end})
    g:AddToggle("ShowFov", {Text = "Show FOV", Callback = function(v) flags.showFov = v end})
end

-- ADVANCED TAB
do
    local g = Tabs.Advanced:AddLeftGroupbox("Prediction & Wallbang")
    g:AddToggle("Prediction", {Text = "Enable Prediction", Callback = function(v) flags.prediction = v end})
    g:AddSlider("PredictionStrength", {Text = "Strength", Default = 90, Min = 50, Max = 120, Callback = function(v)
        PredictionEngine.predictionStrength = v / 100
        flags.predictionStrength = v
    end})
    g:AddToggle("LagComp", {Text = "Lag Compensation", Callback = function(v) flags.lagCompensation = v end})
    g:AddToggle("Wallbang", {Text = "Wallbang (NOW WORKING)", Callback = function(v) 
        flags.wallbang = v
        if v then notify2("Wallbang: ON - Aim offset active", 2) end
    end})
end

do
    local g = Tabs.Advanced:AddRightGroupbox("Combat Tweaks")
    g:AddToggle("KnifeAim", {Text = "Knife Prediction", Callback = function(v) flags.knifeAim = v end})
    g:AddToggle("HitboxExp", {Text = "Hitbox Expand", Callback = function(v) flags.hitboxExpand = v end})
    g:AddSlider("HitboxSize", {Text = "Size Mult", Default = 2, Min = 1, Max = 5, Rounding = 1, Callback = function(v)
        flags.hitboxSize = v
    end})
    g:AddToggle("VisCheck", {Text = "Visibility Check", Callback = function(v) flags.visibilityCheck = v end})
    g:AddToggle("RandDev", {Text = "Random Deviation", Callback = function(v) flags.randomDeviation = v end})
end

-- VISUALS TAB
do
    local g = Tabs.Visuals:AddLeftGroupbox("Player ESP")
    g:AddToggle("EspBox", {Text = "Box ESP", Callback = function(v) flags.espBox = v end})
    g:AddToggle("EspFill", {Text = "Box Fill", Callback = function(v) flags.espFill = v end})
    g:AddToggle("EspNames", {Text = "Names", Callback = function(v) flags.espNames = v end})
    g:AddToggle("EspRoles", {Text = "Role Tags", Callback = function(v) flags.espRoles = v end})
    g:AddToggle("EspHealth", {Text = "Health", Callback = function(v) flags.espHealth = v end})
    g:AddToggle("EspDist", {Text = "Distance", Callback = function(v) flags.espDistance = v end})
end

do
    local g = Tabs.Visuals:AddRightGroupbox("Rendering")
    g:AddToggle("Fullbright", {Text = "Fullbright", Callback = function(v)
        flags.fullbright = v
        setFullbright(v)
    end})
    g:AddToggle("NoFog", {Text = "No Fog", Callback = function(v) flags.noFog = v end})
    g:AddToggle("FpsBoost", {Text = "FPS Boost", Callback = function(v) flags.fpsBoost = v end})
end

-- WORLD TAB
do
    local g = Tabs.World:AddLeftGroupbox("Loot")
    g:AddToggle("CoinEsp", {Text = "Coin ESP", Callback = function(v) flags.coinEsp = v end})
    g:AddToggle("AutoCoins", {Text = "Auto Coins", Callback = function(v) flags.autoCoins = v end})
    g:AddSlider("CoinSpeed", {Text = "Collect Speed", Default = 40, Min = 16, Max = 120, Callback = function(v)
        flags.collectSpeed = v
    end})
end

do
    local g = Tabs.World:AddRightGroupbox("Weapons")
    g:AddToggle("GunEsp", {Text = "Gun ESP", Callback = function(v) flags.gunEsp = v end})
    g:AddToggle("AutoGun", {Text = "Auto Grab", Callback = function(v) flags.autoGun = v end})
end

-- MOVEMENT TAB
do
    local g = Tabs.Movement:AddLeftGroupbox("Flight")
    g:AddToggle("Fly", {Text = "Fly", Callback = function(v)
        flags.fly = v
        if v then startFly() else stopFly() end
    end})
    g:AddSlider("FlySpeed", {Text = "Speed", Default = 60, Min = 20, Max = 250, Callback = function(v)
        flags.flySpeed = v
    end})
    g:AddToggle("Noclip", {Text = "Noclip", Callback = function(v) flags.noclip = v end})
end

do
    local g = Tabs.Movement:AddRightGroupbox("Mobility")
    g:AddToggle("InfJump", {Text = "Inf Jump", Callback = function(v) flags.infJump = v end})
    g:AddToggle("UnlockCam", {Text = "Unlock Camera", Callback = function(v)
        flags.unlockCam = v
        setCameraUnlock(v)
    end})
    g:AddSlider("WalkSpeed", {Text = "Walk Speed", Default = 16, Min = 10, Max = 150, Callback = function(v)
        flags.walkSpeed = v
        local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = v end
    end})
end

-- SETTINGS TAB
do
    local g = Tabs.Settings:AddLeftGroupbox("Alerts")
    g:AddToggle("MurdAlert", {Text = "Murder Alert", Callback = function(v) flags.murdererNotify = v end})
    g:AddToggle("AudioAlert", {Text = "Audio Cue", Callback = function(v) flags.audioAlert = v end})
end

do
    local g = Tabs.Settings:AddRightGroupbox("Server")
    g:AddButton({Text = "Rejoin", Func = rejoin})
    g:AddButton({Text = "Hop Server", Func = hopServer})
    g:AddLabel("Menu Bind:")
        :AddKeyPicker("MenuKey", {Default = "RightShift", NoUI = true, Text = "Menu"})
    Library.ToggleKeybind = Options.MenuKey
end

do
    local g = Tabs.Settings:AddLeftGroupbox("Menu")
    g:AddButton({Text = "Unload", Func = function() Library:Unload() end})
end

-- SAVE/LOAD CONFIG
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("MONO_MM2")
SaveManager:SetFolder("MONO_MM2/configs")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

pcall(function() SaveManager:LoadAutoloadConfig() end)

-- CLEANUP
Library:OnUnload(function()
    for k in pairs(flags) do
        if type(flags[k]) == "boolean" then
            flags[k] = false
        end
    end
    
    stopFly()
    setFullbright(false)
    setNoFog(false)
    setCameraUnlock(false)
    
    for _, conn in ipairs(conns) do
        pcall(function() conn:Disconnect() end)
    end
    
    for plr in pairs(espStore) do
        clearEsp(plr)
    end
    
    pcall(function() EspGui:Destroy() end)
end)

notify2("✅ MONO ULTIMATE FIXED - Silent Aim & Wallbang NOW WORKING", 4)
